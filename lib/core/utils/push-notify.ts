import prisma from "../config/prisma";
import { sendPushNotification } from "./firebase";

export type NotificationType = "ORDER" | "PAYMENT" | "DRIVER" | "WALLET" | "SYSTEM" | "SOS" | "REFERRAL";

/**
 * DB'ga notification yozadi va FCM orqali push yuboradi — birgalikda.
 * Foydalanuvchida FCM token bo'lmasa, push jimgina o'tkazib yuboriladi,
 * DB yozuv baribir saqlanadi (ilova ichida ko'rinishi uchun).
 */
export const notifyUser = async (
  userId: string,
  type: NotificationType,
  title: string,
  body: string
) => {
  await prisma.notification.create({
    data: { userId, type, title, body },
  });

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (user?.fcmToken) {
    await sendPushNotification(user.fcmToken, title, body);
  }
};