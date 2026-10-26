# Razorpay Checkout (razorpay_flutter): its SDK talks to the payment page through
# JavaScript interfaces and reflection, so R8 must keep it as is.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}
# Google Pay (used by Razorpay for UPI intent flows) is optional at runtime.
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.**
-dontwarn proguard.annotation.Keep
-dontwarn proguard.annotation.KeepClassMembers
