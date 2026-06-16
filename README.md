# compress 插件

这个插件定义了一个名为 `compress` 的函数，用于压缩你传给它的文件或目录，并且它支持多种多样的归档和压缩文件类型。

这样你就不需要知道哪个特定的命令可以压缩特定格式，只需执行 `compress <目标文件名.后缀> <源文件...>`，函数就会处理剩下的事情。

要使用它，请将 `compress` 添加到你的 `.zshrc` 文件中的 plugins 数组中：

```zsh
plugins=(... compress)

```

## 可选参数

* `-L, --dereference`    ：跟随符号链接。默认仅打包链接本身，加上此参数会将链接指向的真实实体文件/目录打包进去。
* `-r, --remove`         ：压缩成功后自动删除源文件或源目录。
* `-h, --help`           ：显示帮助信息。

## 支持的文件扩展名

| 扩展名 | 描述 |
| --- | --- |
| `7z` | 7zip 文件 |
| `bz2` | Bzip2 文件 (单文件) |
| `gz` | Gzip 文件 (单文件) |
| `rar` | WinRAR 归档文件 |
| `tar` | Tar 打包文件 |
| `tar.bz2` | 使用 bzip2 压缩的 Tar 打包文件 |
| `tar.gz` | 使用 gzip 压缩的 Tar 打包文件 |
| `tar.xz` | 使用 lzma2 压缩的 Tar 打包文件 |
| `tar.zst` | 使用 zstd 压缩的 Tar 打包文件 |
| `tbz` | 使用 bzip 压缩的 Tar 打包文件 |
| `tbz2` | 使用 bzip2 压缩的 Tar 打包文件 |
| `tgz` | 使用 gzip 压缩的 Tar 打包文件 |
| `txz` | 使用 lzma2 压缩的 Tar 打包文件 |
| `tzst` | 使用 zstd 压缩的 Tar 打包文件 |
| `zip` | Zip 归档文件 |
| `zst` | Zstandard 文件 (zstd, 单文件) |

参见 [归档格式列表](https://en.wikipedia.org/wiki/List_of_archive_formats) 以获取更多关于归档格式的信息。

