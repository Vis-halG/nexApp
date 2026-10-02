package com.thenex.nex_music

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.media.audiofx.Equalizer
import android.media.audiofx.BassBoost
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.mediarouter.app.MediaRouteChooserDialog
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.common.images.WebImage
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NexCastOptions : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions = CastOptions.Builder()
        .setReceiverApplicationId(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID).build()
    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}

class MusicFeatures(private val activity: Activity) {
    private var scanResult: MethodChannel.Result? = null
    private var eq: Equalizer? = null
    private var bass: BassBoost? = null
    private var eqSession = -1
    private val prefs get() = activity.getSharedPreferences("nex_sound", Context.MODE_PRIVATE)
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "scanMusic" -> scan(result)
                "equalizer" -> {
                    attachEffects(call.argument<Number>("session")!!.toInt())
                    val effect = eq!!; val range = effect.bandLevelRange
                    result.success(mapOf("min" to range[0] / 100.0, "max" to range[1] / 100.0,
                        "enabled" to effect.enabled, "bass" to prefs.getInt("bass",0),
                        "bands" to (0 until effect.numberOfBands).map { i -> mapOf("index" to i,
                            "frequency" to effect.getCenterFreq(i.toShort()), "gain" to effect.getBandLevel(i.toShort()) / 100.0) }))
                }
                "setEq" -> {
                    val effect = eq ?: error("Start music before changing sound.")
                    val enabled = call.argument<Boolean>("enabled") == true; effect.enabled = enabled
                    prefs.edit().putBoolean("enabled",enabled).apply()
                    val band = call.argument<Number>("band")!!.toInt()
                    if (band >= 0 && band < effect.numberOfBands) {
                        val value = ((call.argument<Number>("gain")?.toDouble() ?: 0.0) * 100).toInt()
                            .coerceIn(effect.bandLevelRange[0].toInt(),effect.bandLevelRange[1].toInt()).toShort()
                        effect.setBandLevel(band.toShort(),value); prefs.edit().putInt("band_$band",value.toInt()).apply()
                    }
                    result.success(null)
                }
                "setBass" -> { val value = (call.argument<Number>("strength")?.toInt() ?: 0).coerceIn(0,1000)
                    bass?.setStrength(value.toShort()); bass?.enabled = value > 0; prefs.edit().putInt("bass",value).apply(); result.success(null) }
                "translate" -> translate(call,result)
                "openCast" -> { val context = CastContext.getSharedInstance(activity)
                    MediaRouteChooserDialog(activity, androidx.appcompat.R.style.Theme_AppCompat_Dialog).apply { routeSelector = context.mergedSelector ?: androidx.mediarouter.media.MediaRouteSelector.EMPTY; show() }; result.success(null) }
                "castMedia" -> {
                    val client = CastContext.getSharedInstance(activity).sessionManager.currentCastSession?.remoteMediaClient
                    if (client == null) { result.success(false); return }
                    val url = call.argument<String>("url") ?: error("Choose a track.")
                    require(url.startsWith("https://")) { "This device file cannot be cast." }
                    val video = call.argument<Boolean>("video") == true
                    val metadata = MediaMetadata(if (video) MediaMetadata.MEDIA_TYPE_MOVIE else MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
                        putString(MediaMetadata.KEY_TITLE,call.argument<String>("title") ?: "nexApp")
                        putString(MediaMetadata.KEY_ARTIST,call.argument<String>("artist") ?: "")
                        call.argument<String>("art")?.takeIf { it.startsWith("https://") }?.let { addImage(WebImage(Uri.parse(it))) }
                    }
                    val type = call.argument<String>("contentType") ?: if (video || url.contains(".mp4") || url.contains(".m4a")) "video/mp4" else "audio/mpeg"
                    val info = MediaInfo.Builder(url).setContentType(type).setStreamType(MediaInfo.STREAM_TYPE_BUFFERED).setMetadata(metadata).build()
                    client.load(MediaLoadRequestData.Builder().setMediaInfo(info).setAutoplay(true).setCurrentTime(call.argument<Number>("positionMs")?.toLong() ?: 0L).build())
                        .setResultCallback { status -> if (status.status.isSuccess) result.success(true) else result.error("CAST_FAILED","The receiver could not load this track.",null) }
                }
                "castControl" -> { val client = CastContext.getSharedInstance(activity).sessionManager.currentCastSession?.remoteMediaClient
                    when(call.argument<String>("action")) { "play" -> client?.play(); "pause" -> client?.pause(); "stop" -> client?.stop() }; result.success(null) }
                "stopCast" -> { CastContext.getSharedInstance(activity).sessionManager.endCurrentSession(true); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("MUSIC_FEATURE",e.message,null) }
    }
    private fun attachEffects(session: Int) {
        if (eqSession == session && eq != null) return
        eq?.release(); bass?.release(); eq = Equalizer(0,session); eqSession = session
        eq!!.enabled = prefs.getBoolean("enabled",false)
        for (i in 0 until eq!!.numberOfBands) eq!!.setBandLevel(i.toShort(),prefs.getInt("band_$i",0).coerceIn(eq!!.bandLevelRange[0].toInt(),eq!!.bandLevelRange[1].toInt()).toShort())
        try { bass = BassBoost(0,session).apply { val strength = prefs.getInt("bass",0); setStrength(strength.toShort()); enabled = strength > 0 } } catch (_: Exception) { bass = null }
    }
    private fun scan(result: MethodChannel.Result) {
        val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE
        if (ContextCompat.checkSelfPermission(activity,permission) != PackageManager.PERMISSION_GRANTED) {
            if (scanResult != null) { result.error("SCAN_BUSY","Music scan is already waiting for permission.",null); return }
            scanResult = result; ActivityCompat.requestPermissions(activity,arrayOf(permission),7004); return
        }
        Thread {
            try {
                val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                val folderColumn = if (Build.VERSION.SDK_INT >= 29) "relative_path" else "_data"
                val columns = arrayOf("_id","title","artist","album","album_id","artist_id","duration","_size", folderColumn)
                val tracks = mutableListOf<Map<String,Any?>>()
                activity.contentResolver.query(uri,columns,"duration > 0",null,"title COLLATE NOCASE ASC")?.use { cursor ->
                    while (cursor.moveToNext() && tracks.size < 10000) {
                        tracks.add(mapOf("id" to cursor.getLong(0).toString(),"uri" to ContentUris.withAppendedId(uri,cursor.getLong(0)).toString(),
                            "title" to cursor.getString(1),"artist" to cursor.getString(2).takeUnless { it == "<unknown>" }, "album" to cursor.getString(3),
                            "albumId" to cursor.getLong(4).toString(),"artistId" to cursor.getLong(5).toString(),"duration" to cursor.getLong(6),"size" to cursor.getLong(7),
                            "folder" to (if (Build.VERSION.SDK_INT >= 29) cursor.getString(8) else cursor.getString(8)?.substringBeforeLast('/'))))
                    }
                }
                activity.runOnUiThread { result.success(tracks) }
            } catch (e: Exception) { activity.runOnUiThread { result.error("SCAN_FAILED",e.message,null) } }
        }.start()
    }
    fun permissions(code: Int, grants: IntArray) {
        if (code != 7004) return
        val result = scanResult ?: return; scanResult = null
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) scan(result) else result.error("NO_PERMISSION","Allow music access or use Import files.",null)
    }
    private fun translate(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        require(text.isNotBlank() && text.length <= 32000) { "Choose lyrics under 32,000 characters." }
        val target = TranslateLanguage.fromLanguageTag(call.argument<String>("target") ?: "en") ?: error("This language is unavailable.")
        val identifier = LanguageIdentification.getClient()
        identifier.identifyLanguage(text).addOnSuccessListener { language ->
            identifier.close()
            val source = TranslateLanguage.fromLanguageTag(language)
            if (source == null) { result.error("UNKNOWN_LANGUAGE","Could not identify the lyrics language.",null); return@addOnSuccessListener }
            if (source == target) { result.success(text); return@addOnSuccessListener }
            val translator = Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(source).setTargetLanguage(target).build())
            translator.downloadModelIfNeeded(DownloadConditions.Builder().requireWifi().build()).addOnSuccessListener {
                translator.translate(text).addOnSuccessListener { translated -> translator.close(); result.success(translated) }
                    .addOnFailureListener { e -> translator.close(); result.error("TRANSLATION_FAILED",e.message,null) }
            }.addOnFailureListener { e -> translator.close(); result.error("MODEL_DOWNLOAD","Connect to Wi-Fi to download the translation language.",e.message) }
        }.addOnFailureListener { e -> identifier.close(); result.error("LANGUAGE_FAILED",e.message,null) }
    }
    fun dispose() { eq?.release(); bass?.release() }
}
