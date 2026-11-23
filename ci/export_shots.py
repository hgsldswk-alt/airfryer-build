"""Export XCTest attachment PNGs under their stable store/paid names."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHOT = re.compile(r"(?:store-(?:en|zh-Hans|zh-Hant)-\d{2}-[a-z0-9-]+|paid-01-paywall)(?=[_.]|$)")
LANGS = ("en", "zh-Hans", "zh-Hant")
SCENES = ("01-chart", "02-food", "03-flip", "04-save", "05-fryers")
EXPECTED = {f"store-{lang}-{scene}" for lang in LANGS for scene in SCENES} | {"paid-01-paywall"}


def named_attachments(data, exported):
    if isinstance(data, list):
        for item in data:
            yield from named_attachments(item, exported)
    if isinstance(data, dict):
        filename = data.get("exportedFileName")
        name = data.get("suggestedHumanReadableName", data.get("name", ""))
        if isinstance(filename, str) and isinstance(name, str):
            file = exported / Path(filename).name
            match = SHOT.search(name)
            if match and file.suffix.lower() == ".png" and file.is_file():
                yield match[0], file
        for child in data.values():
            if isinstance(child, (list, dict)):
                yield from named_attachments(child, exported)


def exports_from(folder):
    manifest = folder / "manifest.json"
    items = dict(named_attachments(json.loads(manifest.read_text(encoding="utf-8")), folder)) if manifest.is_file() else {}
    for file in folder.rglob("*.png"):
        match = SHOT.search(file.stem)
        if match:
            items.setdefault(match[0], file)
    return items


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output) as directory:
        exported = Path(directory)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path",
                        str(args.result), "--output-path", str(exported)], check=True)
        items = exports_from(exported)
        for name, source in items.items():
            shutil.copy2(source, args.output / f"{name}.png")
    missing = EXPECTED - {file.stem for file in args.output.glob("*.png")}
    if missing:
        sys.exit("Missing screenshots: " + ", ".join(sorted(missing)))
    review = ROOT / "上架资料" / "截图" / "zh-Hans" / "paywall.png"
    review.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.output / "paid-01-paywall.png", review)
    print(f"Exported {len(EXPECTED)} store and review screenshots to {args.output}")


if __name__ == "__main__":
    main()
