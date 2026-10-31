import 'dart:io';

import 'package:simple_live_app/app/log.dart';


extension DirectoryCleaner on Directory {
  Future<void> clear() async {
    
    if (await exists() && await FileSystemEntity.isDirectory(path)) {
      
      List<FileSystemEntity> files = listSync();

      
      for (FileSystemEntity file in files) {
        if (file is File) {
          await file.delete();
          Log.i('删除文件: ${file.path}');
        } else if (file is Directory) {
          await Directory(file.path).delete(recursive: true);
          Log.i('删除文件夹: ${file.path}');
        }
      }

      Log.i('文件夹清空完成');
    } else {
      Log.i('$path 不是一个有效的文件夹');
    }
  }
  
  void clearSync()  {
    if ( existsSync() && FileSystemEntity.isDirectorySync(path)) {
      List<FileSystemEntity> files = listSync();
      for (FileSystemEntity file in files) {
        if (file is File) {
          file.deleteSync();
          Log.i('删除文件: ${file.path}');
        } else if (file is Directory) {
          Directory(file.path).deleteSync(recursive: true);
          Log.i('删除文件夹: ${file.path}');
        }
      }

      Log.i('文件夹清空完成');
    } else {
      Log.i('$path 不是一个有效的文件夹');
    }
  }
}