# compress.plugin.zsh
# 压缩插件，支持多种归档格式，仿照 oh-my-zsh 的 extract 插件编写

alias c=compress

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
        # 复用帮助信息（直接调用自身无参数时的输出）
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
    delete_paths+=("${src:P}")
    if (( follow_symlinks == 1 )); then
      pack_paths+=("${src:A}")
    else
      pack_paths+=("${src:P}")
    fi
  done

  # 3. 智能路径切换优化
  local original_pwd="$PWD"

  if (( ${#sources} == 1 )); then
    local real_src
    if (( follow_symlinks == 1 )); then
      real_src="${sources[1]:A}"
    else
      real_src="${sources[1]:P}"
    fi
    builtin cd -q "${real_src:h}"
    pack_paths=("${real_src:t}")
  else
    local dirs=()
    for src in "${sources[@]}"; do
      if (( follow_symlinks == 1 )); then
        dirs+=("${src:A:h}")
      else
        dirs+=("${src:P:h}")
      fi
    done
    local -a unique_dirs
    unique_dirs=(${(u)dirs})
    if [[ ${#unique_dirs} -eq 1 ]]; then
      local common_parent="${dirs[1]}"
      builtin cd -q "$common_parent"
      pack_paths=()
      for src in "${sources[@]}"; do
        local src_abs
        if (( follow_symlinks == 1 )); then
          src_abs="${src:A}"
        else
          src_abs="${src:P}"
        fi
        local rel_path
        if [[ "$common_parent" == "/" ]]; then
          rel_path="${src_abs#/}"
        else
          rel_path="${src_abs#$common_parent/}"
        fi
        if [[ -z "$rel_path" ]]; then
          rel_path="${src_abs:t}"
        fi
        pack_paths+=("$rel_path")
      done
    fi
  fi

  # 4. 符号链接参数
  local tar_link_flag=""
  local zip_link_flag="-y"

  if (( follow_symlinks == 1 )); then
    tar_link_flag="-h"
    zip_link_flag=""
  fi

  local success=0
  echo "compress: 正在创建压缩包 $archive ..." >&2

  # 5. 检查所需命令是否存在（通用函数）
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
      if [[ -n "$zip_link_flag" ]]; then
        zip $zip_link_flag -r "$archive_path" "${pack_paths[@]}"
      else
        zip -r "$archive_path" "${pack_paths[@]}"
      fi ;;
    (*.7z)
      check_cmd 7z "7z" || return 1
      if (( follow_symlinks == 0 )); then
        7z a -snl "$archive_path" "${pack_paths[@]}"
      else
        7z a "$archive_path" "${pack_paths[@]}"
      fi ;;
    (*.rar)
      check_cmd rar "rar" || return 1
      if (( follow_symlinks == 0 )); then
        rar a -ol "$archive_path" "${pack_paths[@]}"
      else
        rar a "$archive_path" "${pack_paths[@]}"
      fi ;;
    # 单文件压缩格式
    (*.gz|*.bz2|*.xz|*.zst)
      if (( $#pack_paths > 1 )) || [[ -d "${pack_paths[1]:A}" || ( -L "${pack_paths[1]}" && -d "${pack_paths[1]:A}" ) ]]; then
        echo "compress: ${archive:t:e} 格式仅支持单个非目录文件。请使用 .tar.${archive:t:e} 格式。" >&2
        success=1
      else
        local src_file="${pack_paths[1]}"
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

  # 7. 归位
  builtin cd -q "$original_pwd"

  # 8. 可选删除源文件（失败时输出警告但不更改返回码）
  if (( success == 0 && remove_flag == 1 && ${#delete_paths} > 0 )); then
    echo "compress: 压缩成功，正在清理源文件..." >&2
    if ! command rm -rf -- "${delete_paths[@]}"; then
      echo "compress: 警告：压缩成功，但无法清理源文件（权限不足或文件被占用）" >&2
    fi
  fi

  return $success
}