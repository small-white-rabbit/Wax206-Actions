#!/usr/bin/env bash
# Module: General Preparation

clone_repo() {
    # 检查是否存在有效的 git 仓库（必须有 .git 目录）
    if [[ -d "$BUILD_DIR/.git" ]]; then
        echo "构建目录已存在有效的 git 仓库，跳过克隆"
    elif [[ -d $BUILD_DIR ]]; then
        # 目录存在但没有 .git（可能是缓存恢复的 staging_dir），需要重新克隆
        echo "构建目录存在但缺少 .git，保留缓存后重新克隆"
        # 将缓存目录移动到临时位置
        mkdir -p "${BUILD_DIR}_cache_temp"
        if [[ -d "$BUILD_DIR/staging_dir" ]]; then
            mv "$BUILD_DIR/staging_dir" "${BUILD_DIR}_cache_temp/"
        fi
        if [[ -d "$BUILD_DIR/.ccache" ]]; then
            mv "$BUILD_DIR/.ccache" "${BUILD_DIR}_cache_temp/"
        fi
        # 清空构建目录
        rm -rf "$BUILD_DIR"
        
        echo "克隆仓库: $REPO_URL 分支: $REPO_BRANCH"
        if ! git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR; then
            echo "错误：克隆仓库 $REPO_URL 失败" >&2
            exit 1
        fi
        
        # 恢复缓存目录
        if [[ -d "${BUILD_DIR}_cache_temp/staging_dir" ]]; then
            mv "${BUILD_DIR}_cache_temp/staging_dir" "$BUILD_DIR/"
        fi
        if [[ -d "${BUILD_DIR}_cache_temp/.ccache" ]]; then
            mv "${BUILD_DIR}_cache_temp/.ccache" "$BUILD_DIR/"
        fi
        rm -rf "${BUILD_DIR}_cache_temp"
    else
        echo "克隆仓库: $REPO_URL 分支: $REPO_BRANCH"
        if ! git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR; then
            echo "错误：克隆仓库 $REPO_URL 失败" >&2
            exit 1
        fi
    fi
}

clean_up() {
    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "Build directory $BUILD_DIR does not exist"
        return
    fi
    cd "$BUILD_DIR"
    if [[ -f ".config" ]]; then
        \rm -f ".config"
    fi
    if [[ -d "tmp" ]]; then
        \rm -rf "tmp"
    fi
    if [[ -d "logs" ]]; then
        \rm -rf "logs/*"
    fi
    if [[ -d "feeds" ]]; then
        ./scripts/feeds clean
    fi
    mkdir -p "tmp"
    echo "1" >"tmp/.build"
}

reset_feeds_conf() {
    cd "$BUILD_DIR"
    # 确保远程仓库正确指向源码仓库
    local current_origin=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$current_origin" != "$REPO_URL" ]]; then
        echo "修正 origin 远程仓库: $current_origin -> $REPO_URL"
        git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL"
    fi
    # 浅克隆(--depth 1)不会创建远程分支引用(如 origin/main)
    # 先 fetch 建立 origin/$REPO_BRANCH 引用，再 reset
    git fetch origin $REPO_BRANCH --depth 1
    git reset --hard origin/$REPO_BRANCH
    # 使用 -e 排除缓存目录，避免删除 staging_dir 和 .ccache
    git clean -f -d -e staging_dir -e .ccache -e tmp
    if [[ $COMMIT_HASH != "none" ]]; then
        git checkout $COMMIT_HASH
    fi
    # 刷新 staging_dir 中的 stamp 文件时间戳，保持缓存有效性
    if [[ -d "staging_dir" ]]; then
        echo "刷新 staging_dir 中的 stamp 文件时间戳..."
        find staging_dir -type d -name "stamp" -not -path "*target*" | while read -r dir; do
            find "$dir" -type f -exec touch {} +
        done
    fi
    cd - > /dev/null
}
