enum StoragePlatform { android, ios, macos, linux, windows, web, other }

/// Solo Android se activa en esta entrega. Los otros adaptadores nativos quedan
/// preparados, pero requieren validación en el sistema real antes de activarlos.
bool sqliteEnabledFor(StoragePlatform platform) =>
    platform == StoragePlatform.android;
