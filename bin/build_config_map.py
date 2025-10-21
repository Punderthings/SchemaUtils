"""
Scan a Jekyll collection and make a hash of certain fields,
suitable for copying into another Jekyll site _config.yml
Usage:
    python3 build_config_map.py ../opensourceconduct/_cocs identifier commonName
"""

import argparse
import sys
from pathlib import Path
import yaml

YAML_SEPARATOR = '---'

def parse_frontmatter(file_path: Path, field_list: list[str]) -> dict | None:
    """
    Parse file and return relevant frontmatter, otherwise None.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        parts = content.split(YAML_SEPARATOR)
        if len(parts) < 3 or parts[0].strip() != '':
            # Not a valid Jekyll post with frontmatter at the top.
            print(
                f"WARN: Skipping {file_path.name}: "
                "No frontmatter found.", file=sys.stderr
            )
            return None
        
        frontmatter = parts[1]
        data = yaml.safe_load(frontmatter)
        return_hash = {}
        for field in field_list:
            if field in data:
                return_hash[field] = data[field]

        if return_hash:
            return return_hash
        else:
            return None
    except Exception as e:
        print(
            f"ERROR: file read or missing fields {file_path.name}: {e}",
            file=sys.stderr
        )
    return None

def parse_dir(file_path: Path, field_list: list[str]):
    all_data = []
    for file_path in sorted(scanpath.glob('*.md')):
        data = parse_frontmatter(file_path, field_list)
        if data:
            all_data.append(data)

    if not all_data:
        print("No valid Jekyll posts with relevant fields found.")
        return

    return {'config_map': all_data}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description= 'Scan directory for *.md files and parse selected Jekyll frontmatter.'
    )
    parser.add_argument(
        'directory',
        type=str,
        help='The path to the directory to scan.'
    )
    parser.add_argument(
      'fields',
      type=str,
      nargs='+',
      help='List of frontmatter fields to extract.'
    )
    args = parser.parse_args()
    scanpath = Path(args.directory)
    if not scanpath.is_dir():
        print(f"ERROR: path '{scanpath}' is not valid dir.", file=sys.stderr)
        sys.exit(1)
    field_list = args.fields
    output = parse_dir(scanpath, args.fields)
    print(yaml.dump(output, sort_keys=False, indent=2))
