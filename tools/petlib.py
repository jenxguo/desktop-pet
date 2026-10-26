"""Shared helpers for the pet tools: reading pet.json the same way the app does."""
import json
import os
import re
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_SWIFT = os.path.join(ROOT, 'Sources', 'DesktopPet', 'Pet', 'PetConfig.swift')

# Which sprites each moment needs. Missing ones get a stand-in frame (see
# Sources/DesktopPet/Pet/PetSprites.swift), so these are only warnings.
CORE_SPRITES = ['stand', 'walk_0', 'sit', 'sleep']
OPTIONAL_SPRITES = ['sniff', 'dangle']
FEATURE_SPRITES = {
    'photoDrop': ['run_0'],
    'meals': ['eat'],
    'fetch': ['run_0', 'play_bow', 'carry_ball_0'],
    'tidy': ['run_0'],
}
MOMENTS_DIR = os.path.join(ROOT, 'Sources', 'DesktopPet', 'Moments')


def feature_props():
    """moment id -> [prop names], read from each moment's `requiredProps` in Swift."""
    props = {}
    for name in sorted(os.listdir(MOMENTS_DIR)):
        with open(os.path.join(MOMENTS_DIR, name)) as f:
            swift = f.read()
        ident = re.search(r'static let id = "([^"]+)"', swift)
        required = re.search(r'static let requiredProps = \[(.*?)\]', swift, re.S)
        if ident and required:
            props[ident.group(1)] = re.findall(r'"([^"]+)"', required.group(1))
    return props


def builtin_defaults():
    """The app's own defaults, lifted straight out of PetConfig.swift so there's one source of truth."""
    with open(CONFIG_SWIFT) as f:
        swift = f.read()
    match = re.search(r'static let defaultsJSON = """\n(.*?)\n\s*"""', swift, re.S)
    return json.loads(textwrap.dedent(match.group(1)))


def deep_merge(base, override):
    result = dict(base)
    for key, value in override.items():
        if isinstance(result.get(key), dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_pet(pet_dir):
    config = builtin_defaults()
    path = os.path.join(pet_dir, 'pet.json')
    if os.path.exists(path):
        with open(path) as f:
            try:
                config = deep_merge(config, json.load(f))
            except json.JSONDecodeError as e:
                raise SystemExit(f'{path} isn\'t valid JSON — line {e.lineno}, column {e.colno}: {e.msg}')
    return config


def default_pet_dir():
    return os.environ.get('PET_DIR') or os.path.join(ROOT, 'Pet')


def frame_names(sprites_dir, base):
    """walk -> ['walk_0', 'walk_1', ...] up to the first gap, like the app."""
    names = []
    while os.path.exists(os.path.join(sprites_dir, f'{base}_{len(names)}.png')):
        names.append(f'{base}_{len(names)}')
    return names
