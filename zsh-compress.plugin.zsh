# compress.plugin.zsh
# 压缩插件，支持多种归档格式，仿照 oh-my-zsh 的 extract 插件编写
# 修复：符号链接正确处理、删除操作路径安全

alias c=compress

# ---------- 辅助函数 ----------
# 获取不解析符号链接的绝对路径（保留链接自身）
# 使用 realpath -s 如果可用，否则使用 zsh 内置方法（仍会解析父目录，但文件本身不变）
_abs_no_deref() {
  emulate -L zsh
  local file="$1"
  if (( $+commands[realpath] )); then
    realpath -s -- "$file" 2>/dev/null || {
      # fallback: 手动拼接，避免 realpath 失败
      local dir="${file:a:h}"   # 绝对路径的父目录（会解析父目录符号链接，但不影响文件名）
      echo "${dir}/${file:t}"
    }
  else
    # 无 realpath 时，使用 :a 会解析所有符号链接，但为了不解析文件本身，我们只取父目录的绝对路径
    local dir="${file:a:h}"
    echo "${dir}/${file:t}"
  fi
}

# 获取解析符号链接的绝对路径（跟随链接）
_abs_deref() {
  emulate -L zsh
  local file="$1"
  if (( $+commands[realpath] )); then
    realpath -- "$file" 2>/dev/null || echo "${file:A}"
  else
    echo "${file:A}"
  fi
}

# ---------- 主函数 ----------
compress() {
  setopt localoptions noautopushd

  if (( $# < 2 )); then
    cat >&2 <<'EOF'
用法: compress [选项] <压缩包名.后缀> <源文件或目录 ...>

选项:
    -L, --dereference   跟随符号链接（打包链接指向的真实文件/目录，而非链接本身）
    -r, --remove        压缩成功后删除源文件/源目录
    -h, --help          显示此帮助信息

支持的格式:
  7z, bz2, gz, rar, tar, tar.bz2, tar.gz, tar.xz, tar.zst,
  tbz, tbz2, tgz, txz, tzst, zip, zst
EOF
    return 1
  fi

  local remove_flag=0
  local follow_symlinks=0
  local show_help=0
  local archive=""
  local -a sources

  # 1. 解析参数
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        compress
        return 0
        ;;
      -L|--dereference)
        follow_symlinks=1
        shift
        ;;
      -r|--remove)
        remove_flag=1
        shift
        ;;
      -Lr|-rL)
        remove_flag=1
        follow_symlinks=1
        shift
        ;;
      --*)
        echo "compress: 未知长选项 '$1'" >&2
        return 1
        ;;
      -*)
        echo "compress: 未知短选项 '$1'" >&2
        return 1
        ;;
      *)
        if [[ -z "$archive" ]]; then
          archive="$1"
        else
          sources+=("$1")
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$archive" || ${#sources} -eq 0 ]]; then
    echo "compress: 缺少目标压缩包名或源文件" >&2
    return 1
  fi

  # 提前检查压缩包目标目录是否存在
  local archive_path="${archive:A}"
  if [[ ! -d "${archive_path:h}" ]]; then
    echo "compress: 目标目录 '${archive_path:h}' 不存在" >&2
    return 1
  fi

  # 2. 验证源文件并记录路径（删除路径始终使用链接自身）
  local src
  local -a delete_paths
  local -a pack_paths

  for src in "${sources[@]}"; do
    if [[ ! -e "$src" ]]; then
      echo "compress: '$src' 不存在" >&2
      return 1
    fi
    # 删除路径永远是不解析符号链接的绝对路径（用户指定的文件/目录本身）
    delete_paths+=("$(_abs_no_deref "$src")")
    # 打包路径根据 follow_symlinks 决定
    if (( follow_symlinks == 1 )); then
      pack_paths+=("$(_abs_deref "$src")")
    else
      pack_paths+=("$(_abs_no_deref "$src")")
    fi
  done

  # 3. 智能路径切换优化（使用 pack_paths 中的绝对路径来计算相对路径）
  local original_pwd="$PWD"

  if (( ${#sources} == 1 )); then
    # 单文件/目录：切换到其父目录，打包内容为 basename
    local real_src="${pack_paths[1]}"
    builtin cd -q "${real_src:h}"
    pack_paths=("${real_src:t}")
  else
    # 多文件：检查所有源是否在同一父目录下
    local dirs=()
    for src_path in "${pack_paths[@]}"; do
      dirs+=("${src_path:h}")
    done
    local -a unique_dirs
    unique_dirs=(${(u)dirs})
    if [[ ${#unique_dirs} -eq 1 ]]; then
      local common_parent="${dirs[1]}"
      builtin cd -q "$common_parent"
      local -a new_pack_paths
      for src_path in "${pack_paths[@]}"; do
        local rel="${src_path#$common_parent/}"
        if [[ -z "$rel" ]]; then
          # 如果 src_path == common_parent（即源目录本身）
          rel="${src_path:t}"
        fi
        new_pack_paths+=("$rel")
      done
      pack_paths=("${new_pack_paths[@]}")
    fi
    # 如果父目录不同，则保留原绝对路径（不切换目录）
  fi

  # 4. 符号链接参数传递给压缩工具
  local tar_link_flag=""
  local zip_link_flag="-y"
  local sevenz_sym_flag=""    # 7z 默认不跟随链接，需要 -snl 时才不跟随
  local rar_sym_flag=""

  if (( follow_symlinks == 1 )); then
    tar_link_flag="-h"        # tar 跟随链接
    zip_link_flag=""          # zip 默认跟随，需要清空 -y 才能跟随
    # 7z 默认跟随链接？实际测试 7z 默认跟随，且无 -snl 选项。
    # 但保持原意：当不跟随时使用 -snl（但仅某些版本支持）。这里简化处理：不额外配置。
    # rar 默认不跟随，需要 -ol 才不跟随；跟随时不加 -ol
  else
    # 不跟随链接时：
    # tar 默认存储链接本身（不加 -h），zip 需要 -y 存储链接本身
    tar_link_flag=""
    zip_link_flag="-y"
    # 7z 默认跟随？实际上 7z 的行为可能因版本而异。我们尝试用 -snl 来存储链接本身
    sevenz_sym_flag="-snl"    # 仅在压缩时有效，且需 7z 支持
    rar_sym_flag="-ol"        # rar 存储链接本身
  fi

  local success=0
  echo "compress: 正在创建压缩包 $archive ..." >&2

  # 5. 检查所需命令是否存在
  check_cmd() {
    (( $+commands[$1] )) && return 0
    echo "compress: 未安装 '$1' 命令，无法创建 $2 格式压缩包" >&2
    return 1
  }

  # 6. 执行压缩（包含命令存在性检查）
  case "${archive:l}" in
    (*.tar.gz|*.tgz)
      check_cmd tar "tar" || return 1
      if (( $+commands[pigz] )); then
        tar $tar_link_flag -I pigz -cvf "$archive_path" "${pack_paths[@]}"
      else
        check_cmd gzip "gzip" || return 1
        tar $tar_link_flag -zcvf "$archive_path" "${pack_paths[@]}"
      fi ;;
    (*.tar.bz2|*.tbz|*.tbz2)
      check_cmd tar "tar" || return 1
      if (( $+commands[pbzip2] )); then
        tar $tar_link_flag -I pbzip2 -cvf "$archive_path" "${pack_paths[@]}"
      else
        check_cmd bzip2 "bzip2" || return 1
        tar $tar_link_flag -jcvf "$archive_path" "${pack_paths[@]}"
      fi ;;
    (*.tar.xz|*.txz)
      check_cmd tar "tar" || return 1
      if (( $+commands[pixz] )); then
        tar $tar_link_flag -I pixz -cvf "$archive_path" "${pack_paths[@]}"
      else
        check_cmd xz "xz" || return 1
        tar $tar_link_flag -Jcvf "$archive_path" "${pack_paths[@]}"
      fi ;;
    (*.tar.zst|*.tzst)
      check_cmd tar "tar" || return 1
      check_cmd zstd "zstd" || return 1
      tar $tar_link_flag -I "zstd -T0" -cvf "$archive_path" "${pack_paths[@]}" ;;
    (*.tar)
      check_cmd tar "tar" || return 1
      tar $tar_link_flag -cvf "$archive_path" "${pack_paths[@]}" ;;
    (*.zip)
      check_cmd zip "zip" || return 1
      # 注意：zip 的 -y 选项用于存储符号链接本身（不跟随）
      # 当 zip_link_flag 为空时，zip 默认跟随链接
      if [[ -n "$zip_link_flag" ]]; then
        zip $zip_link_flag -r "$archive_path" "${pack_paths[@]}"
      else
        zip -r "$archive_path" "${pack_paths[@]}"
      fi ;;
    (*.7z)
      check_cmd 7z "7z" || return 1
      # 7z 的 -snl 用于存储符号链接（不跟随），若未开启则默认跟随
      if (( follow_symlinks == 0 )); then
        7z a $sevenz_sym_flag "$archive_path" "${pack_paths[@]}"
      else
        7z a "$archive_path" "${pack_paths[@]}"
      fi ;;
    (*.rar)
      check_cmd rar "rar" || return 1
      # rar 的 -ol 用于存储链接本身，不加则跟随
      if (( follow_symlinks == 0 )); then
        rar a $rar_sym_flag "$archive_path" "${pack_paths[@]}"
      else
        rar a "$archive_path" "${pack_paths[@]}"
      fi ;;
    # 单文件压缩格式
    (*.gz|*.bz2|*.xz|*.zst)
      if (( $#pack_paths > 1 )) || [[ -d "${pack_paths[1]}" || ( -L "${pack_paths[1]}" && -d "${pack_paths[1]:A}" ) ]]; then
        echo "compress: ${archive:t:e} 格式仅支持单个非目录文件。请使用 .tar.${archive:t:e} 格式。" >&2
        success=1
      else
        local src_file="${pack_paths[1]}"
        # 对于单文件压缩，不涉及符号链接选项，直接压缩文件内容
        case "${archive:l}" in
          *.gz)
            check_cmd gzip "gzip" || { success=1; break; }
            if (( $+commands[pigz] )); then
              pigz -c -- "$src_file" > "$archive_path"
            else
              gzip -c -- "$src_file" > "$archive_path"
            fi ;;
          *.bz2)
            check_cmd bzip2 "bzip2" || { success=1; break; }
            if (( $+commands[pbzip2] )); then
              pbzip2 -c -- "$src_file" > "$archive_path"
            else
              bzip2 -c -- "$src_file" > "$archive_path"
            fi ;;
          *.xz)
            check_cmd xz "xz" || { success=1; break; }
            xz -c -- "$src_file" > "$archive_path" ;;
          *.zst)
            check_cmd zstd "zstd" || { success=1; break; }
            if (( $+commands[pzstd] )); then
              pzstd -c -- "$src_file" > "$archive_path"
            else
              zstd -T0 -c -- "$src_file" > "$archive_path"
            fi ;;
        esac
      fi ;;
    *)
      echo "compress: 不支持的压缩格式 '${archive:t}'" >&2
      success=1 ;;
  esac

  # 记录压缩命令的退出码
  local rc=$?
  (( success == 0 )) && success=$rc

  # 7. 归位到原始目录
  builtin cd -q "$original_pwd"

  # 8. 可选删除源文件
  if (( success == 0 && remove_flag == 1 && ${#delete_paths} > 0 )); then
    echo "compress: 压缩成功，正在清理源文件..." >&2
    # 切换到根目录再删除，确保绝对路径不被当前目录影响
    builtin cd -q /
    if ! command rm -rf -- "${delete_paths[@]}"; then
      echo "compress: 警告：压缩成功，但无法清理源文件（权限不足或文件被占用）" >&2
    fi
    builtin cd -q "$original_pwd"
  fi

  return $success
}