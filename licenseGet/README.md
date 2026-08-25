# MacWindowButtons 激活码生成器

`generate_license.py` 只使用 Python 标准库。管理员首次配置时运行：

```bash
python3 licenseGet/generate_license.py --init-key
```

生成的 `license_private_key.json` 已被 Git 忽略。请离线备份；不要把它提交到仓库、放进 DMG 或发给用户。打印出的 Base64 公钥必须与应用中 `LicenseVerifier.publicKeyBase64` 的值一致。

日常签发直接运行：

```bash
python3 licenseGet/generate_license.py
```

在 Finder 中双击 `run_license_generator.command` 也会打开终端并进入相同的交互流程。

依次输入用户提供的加密设备码和激活天数。加密设备码是应用根据硬件 UUID 生成的不可逆 SHA-256 指纹，不包含可还原的原始机器信息。天数为 `0` 时生成永久激活码。也可以非交互运行：

```bash
python3 licenseGet/generate_license.py --machine-code 'MWB1-...' --days 30
```
