package com.goway.goway_app

import android.app.Application
import com.yandex.mapkit.MapKitFactory

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Yandex MapKit kalitini ilova ishga tushganda, xarita
        // widget'lari yaratilishidan oldin sozlaymiz.
        MapKitFactory.setApiKey("9e955d31-139b-469f-879b-4ef0ec890c60")
    }
}