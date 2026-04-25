# -*- mode: python ; coding: utf-8 -*-
import os

from PyInstaller.utils.hooks import collect_all, collect_data_files


project_root = os.path.abspath(os.path.join(SPECPATH, ".."))


def optional_collect_all(package_name):
    try:
        return collect_all(package_name)
    except Exception:
        return [], [], []


datas = []
binaries = []
hiddenimports = [
    "ctranslate2",
    "mlx_whisper",
    "mlx_whisper.audio",
    "mlx_whisper.decoding",
    "mlx_whisper.load_models",
    "mlx_whisper.timing",
    "mlx_whisper.tokenizer",
    "mlx_whisper.transcribe",
    "mlx_whisper.version",
    "mlx_whisper.whisper",
    "mlx_whisper.writers",
]

datas += collect_data_files("faster_whisper")
datas += collect_data_files("mlx_whisper")

for package_name in ("mlx",):
    package_datas, package_binaries, package_hiddenimports = optional_collect_all(
        package_name
    )
    datas += package_datas
    binaries += package_binaries
    hiddenimports += package_hiddenimports


a = Analysis(
    [os.path.join(project_root, "python", "whisper_server.py")],
    pathex=[project_root],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["torch", "torchaudio", "torchvision", "tensorboard"],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="whisper_server",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
