#!/bin/zsh

script_directory="$(cd "$(dirname "$0")" && pwd)"
python_path="$script_directory/.venv/bin/python3"

if [[ ! -x "$python_path" ]] || \
    ! "$python_path" -c 'import cryptography' >/dev/null 2>&1; then
    echo "首次使用需要在独立环境中安装 cryptography 加密库。"
    read "install_reply?是否现在安装？需要连接网络 [y/N]："
    echo
    if [[ "$install_reply" == [yY] ]]; then
        /usr/bin/python3 -m venv "$script_directory/.venv" && \
            "$python_path" -m pip install -r "$script_directory/requirements.txt"
        if [[ $? -ne 0 ]]; then
            echo "依赖安装失败，请检查网络后重试。"
            echo "按任意键关闭此窗口。"
            read -k 1
            exit 1
        fi
    else
        echo "已取消。也可以按照 README.md 手动完成离线环境配置。"
        echo "按任意键关闭此窗口。"
        read -k 1
        exit 1
    fi
fi

"$python_path" "$script_directory/generate_license.py"
exit_status=$?

echo
if [[ $exit_status -eq 0 ]]; then
    echo "激活码生成完成。"
else
    echo "激活码生成失败，请检查上面的错误信息。"
fi
echo "按任意键关闭此窗口。"
read -k 1
exit $exit_status
