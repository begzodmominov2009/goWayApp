import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

YandexMapController? _mapController;

void updateWebMapLocation(double lat, double lng) {
  // Native da bu funksiya ishlatilmaydi
}

void setMapDarkMode(bool isDark) {
  // Native da hozircha kerak emas (keyinchalik xarita uslubini
  // isDark bo'yicha o'zgartirish mumkin bo'ladi)
}

Widget buildMap({required double lat, required double lng, bool isDark = false}) {
  final point = Point(latitude: lat, longitude: lng);

  return YandexMap(
    mapObjects: [
      PlacemarkMapObject(
        mapId: const MapObjectId('driver'),
        point: point,
        opacity: 1,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromAssetImage(
              'assets/icons/truck_marker.png',
            ),
            scale: 0.15,
          ),
        ),
      ),
    ],
    onMapCreated: (controller) {
      _mapController = controller;
      controller.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: point, zoom: 14),
        ),
      );
    },
  );
}