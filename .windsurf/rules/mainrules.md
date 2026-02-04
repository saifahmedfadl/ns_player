---
trigger: always_on
---
# 📋 PROJECT_CHANGELOG.md
> **Single Source of Truth** - سجل جميع التغييرات والقرارات المعمارية

**آخر تحديث:** 10 يناير 2026  
**المسؤول:** AI Software Engineer + Technical Architect

---

## 📌 قواعد هذا الملف

1. **كل تعديل** يجب أن يُوثق هنا قبل التنفيذ
2. **لا يُحذف** أي سجل - فقط يُضاف الجديد
3. **يُراجع** قبل أي عمل جديد لتجنب التكرار
4. **يُحدث** بعد كل commit

---

## 🏗️ البنية الحالية للمشروع

### المكونات الرئيسية:
| المكون | المسار | الوصف |
|--------|--------|-------|
| **Server** | `/server` | Node.js + Express + TypeScript |
| **Admin Panel** | `/admin` | React + TypeScript + TailwindCSS |
| **Chrome Extension** | `/chrome-extension` | إضافة المتصفح |
| **AWS Batch** | `/aws-batch` | Docker + HandBrake للمعالجة |

### الخدمات الأساسية (Services):
| الخدمة | الملف | المسؤولية |
|--------|-------|-----------|
| **VideoProcessingOrchestrator** | `video-processing-orchestrator.service.ts` | تنسيق مراحل المعالجة |
| **AWSBatchService** | `aws-batch.service.ts` | التكامل مع AWS Batch |
| **StorageService** | `storage.service.ts` | التعامل مع R2/S3 |
| **SSEService** | `sse.service.ts` | Real-time updates |
| **VideoService** | `video.service.ts` | إدارة الفيديوهات |

### قاعدة البيانات (Models):
- `Video` - بيانات الفيديو
- `VideoProcessingSession` - جلسات المعالجة
- `ProcessingEvent` - أحداث المعالجة
- `ProcessingDecision` - قرارات الـ Orchestrator
- `Account` - حسابات العملاء
- `ViewSession` - جلسات المشاهدة

---

## 📝 سجل التغييرات (Changelog)

### [2026-01-10] - إنشاء ملف التتبع
- **ما تم:** إنشاء `PROJECT_CHANGELOG.md` كـ Single Source of Truth
- **السبب:** تطبيق قواعد العمل الجديدة لمنع النسيان والتكرار
- **الملفات المتأثرة:** `PROJECT_CHANGELOG.md` (جديد)
- **المخاطر:** لا يوجد
- **التأثير:** تحسين التوثيق والتتبع

---

## 🔧 القرارات المعمارية (Architectural Decisions)

### [ADR-001] استخدام AWS Batch للمعالجة
- **التاريخ:** يناير 2026
- **القرار:** استخدام AWS Batch مع Spot Instances بدلاً من المعالجة المحلية
- **السبب:** توفير التكاليف (90% أقل) + قابلية التوسع
- **البديل المرفوض:** AWS MediaConvert (أغلى 37 ضعف)

### [ADR-002] نظام Orchestrator للمعالجة
- **التاريخ:** يناير 2026
- **القرار:** استخدام State Machine مع Lock mechanism
- **السبب:** ضمان Idempotency ومنع التكرار
- **المراحل:** METADATA → COMPRESS → THUMBNAILS → TRANSCODE

### [ADR-003] HLS Adaptive Streaming
- **التاريخ:** يناير 2026
- **القرار:** دعم جودات متعددة (360p, 480p, 720p, 1080p)
- **السبب:** تجربة مستخدم أفضل على مختلف سرعات الإنترنت
- **الأولوية:** 360p أولاً للتشغيل السريع

---

## ⚠️ المشاكل المعروفة (Known Issues)

| المشكلة | الحالة | الملاحظات |
|---------|--------|-----------|
| CORS في R2 | ⚠️ جاري العمل | ضبط سياسات Cloudflare |

---

## 🚀 خطة التطوير (Roadmap)

| الميزة | الأولوية | الحالة |
|--------|----------|--------|
| YouTube OAuth 2.0 | متوسطة | مخطط |
| تحسين Retry Logic | عالية | مكتمل |

---

## 📚 مراجع مهمة

- `MASTER_PROJECT_REFERENCE.md` - الدليل الشامل
- `COMPREHENSIVE_PROJECT_SUMMARY.md` - ملخص المشروع
- `/server/.env.example` - متغيرات البيئة
- `/aws-batch/README.md` - دليل AWS Batch

---

**نهاية الملف - يُحدث مع كل تغيير**
