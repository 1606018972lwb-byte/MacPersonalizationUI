# MacWindowButtons 激活码生成器

发码器使用 `cryptography` 处理 Ed25519 签名和加密 PKCS#8 私钥。首次使用前创建独立环境：

```bash
python3 -m venv licenseGet/.venv
licenseGet/.venv/bin/python3 -m pip install -r licenseGet/requirements.txt
```

在 Finder 中双击 `run_license_generator.command` 时，如果尚未配置环境，也可以确认后自动完成上述安装。需要离线使用时，应先联网安装依赖，再将管理员机器断网。

## 迁移现有私钥

仓库曾使用明文 `license_private_key.json`。运行以下命令，把同一把私钥转换为口令加密的 `license_private_key.pem`：

```bash
licenseGet/.venv/bin/python3 licenseGet/generate_license.py --migrate-key
```

设置至少 12 个字符的强口令。工具会加载新文件并核对公钥，验证成功后才删除旧版明文 JSON；应用中的公钥、已经签发的激活码和用户现有激活状态都不会变化。

不要使用 `--init-key --force` 代替迁移，否则会生成不同的私钥，旧激活码将失效。迁移前建议把旧私钥离线备份到加密介质，迁移后应分别保存加密 PEM 和口令。

## 日常签发

直接双击 `run_license_generator.command`，或者运行：

```bash
licenseGet/.venv/bin/python3 licenseGet/generate_license.py
```

每次签发先输入私钥口令，再依次输入用户提供的加密设备码和激活天数。加密设备码是应用根据硬件 UUID 生成的不可逆 SHA-256 指纹，不包含可还原的原始机器信息；天数为 `0` 时生成永久激活码。

也可以在命令行提供非敏感参数，私钥口令仍只通过隐藏输入读取，不支持命令行参数或环境变量传入：

```bash
licenseGet/.venv/bin/python3 licenseGet/generate_license.py \
  --machine-code 'MWB1-...' \
  --days 30
```

`license_private_key.pem` 和旧版 JSON 均已被 Git 忽略。绝不能把它们提交到仓库、放进 DMG 或发给用户。
