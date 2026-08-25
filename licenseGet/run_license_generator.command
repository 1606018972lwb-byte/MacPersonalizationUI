#!/bin/zsh

script_directory="$(cd "$(dirname "$0")" && pwd)"
/usr/bin/python3 "$script_directory/generate_license.py"
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
