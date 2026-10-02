import {readFile} from 'node:fs/promises';
import {after,before,beforeEach,test} from 'node:test';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,getDocs,deleteDoc,collection,query,where,writeBatch,updateDoc,serverTimestamp,Timestamp,arrayUnion} from 'firebase/firestore';
let env;
before(async () => {env=await initializeTestEnvironment({projectId:'demo-nexapp',firestore:{host:'127.0.0.1',port:8086,rules:await readFile(new URL('../firestore.rules',import.meta.url),'utf8')}});});
beforeEach(async () => env.clearFirestore());
after(async () => env?.cleanup());
const db = uid => env.authenticatedContext(uid).firestore();
const playlist = () => ({id:'playlist1',ownerUid:'owner',name:'Mix',cover:'🎧',description:'',public:false,deleted:false,updatedAt:Date.now(),tracks:[],members:['owner'],editors:['owner']});
async function seed() {await setDoc(doc(db('owner'),'playlists/playlist1'),playlist());}
async function join(uid,token,editor=false) {
  const client=db(uid),batch=writeBatch(client);
  batch.set(doc(client,`users/${uid}/playlistJoins/playlist1`),{inviteId:token,createdAt:serverTimestamp()});
  batch.update(doc(client,'playlists/playlist1'),{members:arrayUnion(uid),...(editor?{editors:arrayUnion(uid)}:{}),updatedAt:Date.now()});
  return batch.commit();
}
test('private activity and listening stats stay within the account',async () => {
  await assertSucceeds(setDoc(doc(db('alice'),'users/alice/activity/track'),{song:{id:'track'},liked:true,likedAt:1}));
  await assertFails(getDoc(doc(db('bob'),'users/alice/activity/track')));
  await assertFails(setDoc(doc(db('bob'),'users/alice/activity/track'),{song:{id:'track'}}));
});
test('playlist ownership cannot be forged or changed and private reads require membership',async () => {
  await seed(); await assertFails(getDoc(doc(db('bob'),'playlists/playlist1')));
  await assertFails(setDoc(doc(db('bob'),'playlists/fake'),{...playlist(),id:'fake'}));
  await assertFails(updateDoc(doc(db('owner'),'playlists/playlist1'),{ownerUid:'bob'}));
  await assertSucceeds(updateDoc(doc(db('owner'),'playlists/playlist1'),{public:true}));
  await assertSucceeds(getDoc(doc(db('bob'),'playlists/playlist1')));
});
test('valid invite joins a private playlist, editors can edit tracks, viewers cannot escalate',async () => {
  await seed(); const owner=db('owner');
  await setDoc(doc(owner,'playlistInvites/editor'),{playlistId:'playlist1',ownerUid:'owner',editor:true,createdAt:serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+3600000)});
  await assertSucceeds(join('bob','editor',true));
  await assertSucceeds(updateDoc(doc(db('bob'),'playlists/playlist1'),{tracks:[{id:'song',title:'Track'}],updatedAt:Date.now()}));
  await assertFails(updateDoc(doc(db('bob'),'playlists/playlist1'),{public:true}));
  await setDoc(doc(owner,'playlistInvites/viewer'),{playlistId:'playlist1',ownerUid:'owner',editor:false,createdAt:serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+3600000)});
  await assertFails(join('eve','viewer',true));
  await assertSucceeds(join('eve','viewer'));
  await assertFails(updateDoc(doc(db('eve'),'playlists/playlist1'),{name:'Hacked'}));
});
test('room guests can join/request/vote but cannot control host playback or alter another vote',async () => {
  const room=doc(db('host'),'listeningRooms/room1');
  await assertSucceeds(setDoc(room,{name:'Room',hostUid:'host',members:['host'],active:true,createdAt:serverTimestamp(),updatedAt:serverTimestamp(),current:null,playing:false,positionMs:0}));
  const guest=db('guest'); await assertSucceeds(updateDoc(doc(guest,'listeningRooms/room1'),{members:arrayUnion('guest')}));
  await assertFails(updateDoc(doc(guest,'listeningRooms/room1'),{playing:true}));
  await assertSucceeds(setDoc(doc(guest,'listeningRooms/room1/requests/request1'),{song:{id:'a',title:'Track'},requestedBy:'guest',votes:{},createdAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(guest,'listeningRooms/room1/requests/request1'),{'votes.guest':true}));
  await assertFails(updateDoc(doc(guest,'listeningRooms/room1/requests/request1'),{'votes.host':true}));
  await assertFails(getDoc(doc(db('stranger'),'listeningRooms/room1/requests/request1')));
});

test('public playlists never expose invite tokens; join proofs are private and revoked links fail',async () => {
  await seed();const owner=db('owner');
  await updateDoc(doc(owner,'playlists/playlist1'),{public:true});
  await setDoc(doc(owner,'playlistInvites/secret'),{playlistId:'playlist1',ownerUid:'owner',editor:true,createdAt:serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+3600000)});
  await assertSucceeds(join('bob','secret',true));
  const visible=(await assertSucceeds(getDoc(doc(db('outsider'),'playlists/playlist1')))).data();
  if ('joinToken' in visible || 'inviteId' in visible) throw Error('Public invitation token leak');
  await assertFails(getDoc(doc(db('outsider'),'users/bob/playlistJoins/playlist1')));
  await assertFails(updateDoc(doc(db('outsider'),'playlists/playlist1'),{members:arrayUnion('outsider'),editors:arrayUnion('outsider')}));
  await assertFails(getDocs(collection(db('outsider'),'playlistInvites')));
  await assertSucceeds(getDocs(query(collection(owner,'playlistInvites'),where('ownerUid','==','owner'))));
  await assertSucceeds(deleteDoc(doc(owner,'playlistInvites/secret')));
  await assertFails(join('outsider','secret',true));
});
