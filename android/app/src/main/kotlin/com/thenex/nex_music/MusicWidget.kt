package com.thenex.nex_music

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews
import org.json.JSONObject

class MusicWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { for (id in ids) render(context,manager,id) }
    companion object {
        fun save(context: Context, data: String) {
            context.getSharedPreferences("nex_widgets",Context.MODE_PRIVATE).edit().putString("data",data).apply()
            val manager = AppWidgetManager.getInstance(context)
            for (id in manager.getAppWidgetIds(ComponentName(context,MusicWidget::class.java))) render(context,manager,id)
        }
        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val json = try { JSONObject(context.getSharedPreferences("nex_widgets",Context.MODE_PRIVATE).getString("data","{}") ?: "{}") } catch (_: Exception) { JSONObject() }
            val current = json.optJSONObject("now")
            val view = RemoteViews(context.packageName,R.layout.music_widget)
            view.setTextViewText(R.id.widget_title,current?.optString("title") ?: "nexMusic")
            view.setTextViewText(R.id.widget_artist,current?.optString("subtitle") ?: "Tap to choose music")
            view.setTextViewText(R.id.widget_toggle,if (current?.optBoolean("playing") == true) "Ⅱ" else "▶")
            view.setOnClickPendingIntent(R.id.widget_title,NexPhone.openAppIntent(context,"player",id*10))
            view.setOnClickPendingIntent(R.id.widget_previous,NexPhone.openAppIntent(context,"previous",id*10+1))
            view.setOnClickPendingIntent(R.id.widget_toggle,NexPhone.openAppIntent(context,"toggle",id*10+2))
            view.setOnClickPendingIntent(R.id.widget_next,NexPhone.openAppIntent(context,"next",id*10+3))
            val picks = json.optJSONArray("liked")?.takeIf { it.length() > 0 } ?: json.optJSONArray("recent") ?: json.optJSONArray("latest")
            val titleIds = intArrayOf(R.id.widget_song1,R.id.widget_song2,R.id.widget_song3)
            for (i in 0..2) {
                val song = picks?.optJSONObject(i); view.setTextViewText(titleIds[i],song?.optString("title") ?: "Open library")
                view.setOnClickPendingIntent(titleIds[i],NexPhone.openAppIntent(context,song?.optString("id")?.let { "play:$it" } ?: "downloads",id*10+4+i))
            }
            manager.updateAppWidget(id,view)
        }
    }
}
