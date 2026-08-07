/// NAS 路径拼接工具。
///
/// 远端 NAS 路径（SMB / WebDAV / 群晖 / 飞牛 / 绿联 / FTP / SFTP / S3 …）统一使用
/// POSIX 风格分隔符 `/`；只有 `LocalFileSystem` 会在 Windows 宿主上返回
/// `C:\Users\...` 这类原生路径。
///
/// 直接使用 `p.join` / `p.dirname` 会采用**宿主平台**的分隔符，在 Windows 上把
/// 远端路径拼成 `/music/album\folder.jpg`，写入远端时落到错误位置或直接失败；
/// 反过来对本地 Windows 路径强行用 `p.posix` 又会让 `dirname` 返回 `.`。
///
/// 因此这里按**路径自身的风格**选择 `p.Context`。
library;

import 'package:path/path.dart' as p;

/// 盘符（`C:\` / `C:/`）或 UNC（`\\server\share`）开头视为 Windows 本地路径。
final RegExp _windowsStyle = RegExp(r'^[A-Za-z]:[\\/]|^\\\\');

/// 判断 [path] 是否为 Windows 本地风格路径。
bool isWindowsStylePath(String path) => _windowsStyle.hasMatch(path);

/// 返回适用于 [path] 的 path context：Windows 本地路径用 [p.windows]，其余用 [p.posix]。
p.Context nasPathContext(String path) =>
    isWindowsStylePath(path) ? p.windows : p.posix;

/// 按 [base] 自身风格拼接子路径，避免在 Windows 宿主上给远端路径混入 `\`。
String nasPathJoin(String base, String child) =>
    nasPathContext(base).join(base, child);

/// 按 [path] 自身风格取父目录。
String nasPathDirname(String path) => nasPathContext(path).dirname(path);

/// 按 [path] 自身风格取文件名。
String nasPathBasename(String path) => nasPathContext(path).basename(path);

/// 按 [path] 自身风格取不含扩展名的文件名。
String nasPathBasenameWithoutExtension(String path) =>
    nasPathContext(path).basenameWithoutExtension(path);

/// 按 [path] 自身风格取扩展名（含 `.`）。
String nasPathExtension(String path) => nasPathContext(path).extension(path);
