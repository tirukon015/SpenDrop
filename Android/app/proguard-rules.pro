# kotlinx.serialization: keep generated serializers
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.spendrop.**$$serializer { *; }
-keepclassmembers class com.spendrop.** { *** Companion; }
-keepclasseswithmembers class com.spendrop.** { kotlinx.serialization.KSerializer serializer(...); }

# PdfBox-Android optional JPEG2000 decoder is not bundled
-dontwarn com.gemalto.jp2.**
-dontwarn org.bouncycastle.**
