from pathlib import Path

root = Path(__file__).resolve().parents[1] / "lib"

kyc = root / "features/Auth/AuthPresenter/kyc_verification_screen.dart"
text = kyc.read_text(encoding="utf-8")
marker = "/// Hosted Didit verification"
idx = text.find(marker)
if idx >= 0:
    kyc.write_text(text[:idx].rstrip() + "\n", encoding="utf-8")
    print("truncated kyc_verification_screen")
else:
    print("kyc marker already gone")

skip = {"kyc_session_ui_io.dart", "android_maps_io.dart"}
count = 0
for f in root.rglob("*.dart"):
    if f.name in skip:
        continue
    src = f.read_text(encoding="utf-8")
    n = src
    n = n.replace(
        "import 'dart:io' show File;",
        "import 'package:universal_io/io.dart' show File;",
    )
    n = n.replace(
        "import 'dart:io' show Platform;",
        "import 'package:universal_io/io.dart' show Platform;",
    )
    n = n.replace("import 'dart:io';", "import 'package:universal_io/io.dart';")
    n = n.replace(
        "import 'package:flutter_local_notifications/flutter_local_notifications.dart';",
        "import 'package:vero360_app/native/local_notifications.dart';",
    )
    n = n.replace(
        "import 'package:local_auth/local_auth.dart';",
        "import 'package:vero360_app/native/biometrics.dart';",
    )
    n = n.replace(
        "import 'package:saver_gallery/saver_gallery.dart';",
        "import 'package:vero360_app/native/gallery_saver.dart';",
    )
    if n != src:
        f.write_text(n, encoding="utf-8")
        count += 1
print(f"updated {count} dart files")
