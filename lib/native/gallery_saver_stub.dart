class SaveResult {
  const SaveResult({this.isSuccess = false, this.errorMessage});
  final bool isSuccess;
  final String? errorMessage;
}

class SaverGallery {
  static Future<SaveResult> saveImage(
    List<int> bytes, {
    int quality = 80,
    String? extension,
    String? fileName,
    String? androidRelativePath,
    bool skipIfExists = false,
  }) async {
    return const SaveResult(
      errorMessage: 'Saving to the gallery is available in the iOS/Android app.',
    );
  }

  static Future<SaveResult> saveFile({
    required String filePath,
    required String fileName,
    String? androidRelativePath,
    bool skipIfExists = false,
  }) async {
    return const SaveResult(
      errorMessage: 'Saving files is available in the iOS/Android app.',
    );
  }
}
