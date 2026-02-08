package com.downloader;

public class DownloadExample {
  public static void main(String[] args) {
    if (args.length < 1) {
      System.out.println("Usage: java DownloadExample <url> [output-dir] [filename]");
      System.out.println("Example: java DownloadExample https://example.com/file.pdf downloads myfile.pdf");
      System.exit(1);
    }

    String url = args[0];
    String outputDir = args.length > 1 ? args[1] : "downloads";
    String fileName = args.length > 2 ? args[2] : extractFileName(url);

    System.out.println("Downloading: " + url);
    System.out.println("Saving to: " + outputDir + "/" + fileName);

    PRDownloader.initialize(new Context());

    Response response = PRDownloader.download(url, outputDir, fileName)
        .build()
        .executeSync();

    if (response.isSuccessful()) {
      System.out.println("✓ Download completed successfully!");
    } else if (response.getError() != null) {
      Error error = response.getError();
      if (error.isServerError()) {
        System.err.println("✗ Server error: " + error.getServerErrorMessage());
      } else if (error.isConnectionError()) {
        System.err.println("✗ Connection error: " + error.getConnectionException().getMessage());
      }
      System.exit(1);
    } else if (response.isCancelled()) {
      System.out.println("Download was cancelled");
    } else if (response.isPaused()) {
      System.out.println("Download was paused");
    }

    PRDownloader.shutDown();
  }

  private static String extractFileName(String url) {
    String path = url.substring(url.lastIndexOf('/') + 1);
    int queryIndex = path.indexOf('?');
    if (queryIndex > 0) {
      path = path.substring(0, queryIndex);
    }
    return path.isEmpty() ? "downloaded-file" : path;
  }
}
