# Builds the BAS and MAC language icons, media/basic.svg and media/macro10.svg, from Seti UI's ASM glyph (MIT,
# Copyright (c) 2014 Jesse Weed; see ThirdPartyNotices.txt): its A, S and M outlines as they are, with a B and a C
# drawn to the same height and stroke. Font units, y up, baseline 387.
#
# Needs fonttools (pip install fonttools). Run with VS Code's Seti font and the three output paths, such as:
#   python scripts/language-icons.py "<VS Code>/resources/app/extensions/theme-seti/icons/seti.woff"
#       media/basic.svg media/macro10.svg asm-reference.svg
# The third is Seti's own ASM, drawn the same way, to compare against.
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

font = TTFont(sys.argv[1])
glyphs = font.getGlyphSet()
name = font.getBestCmap()[0xE004]
recording = DecomposingRecordingPen(glyphs)
glyphs[name].draw(recording)

contours, current = [], []
for op, args in recording.value:
    current.append((op, args))
    if op == "closePath":
        contours.append(current)
        current = []

BASE = 387
# Seti's letters, each as its contours and its left and right edges.
seti = {"A": (contours[0] + contours[1], 187, 394), "S": (contours[2], 405, 586), "M": (contours[3], 603, 813)}

# Drawn letters in local units (x from 0, y from the baseline), the same 225 tall with 30-38 unit strokes.
drawn = {
    "B": ([
        ("moveTo", [(0, 0)]), ("lineTo", [(0, 225)]), ("lineTo", [(105, 225)]),
        ("qCurveTo", [(160, 225), (160, 170)]), ("qCurveTo", [(160, 130), (125, 118)]),
        ("qCurveTo", [(170, 105), (170, 60)]), ("qCurveTo", [(170, 0), (110, 0)]), ("closePath", []),
        ("moveTo", [(36, 195)]), ("lineTo", [(100, 195)]), ("qCurveTo", [(124, 195), (124, 163)]),
        ("qCurveTo", [(124, 132), (100, 132)]), ("lineTo", [(36, 132)]), ("closePath", []),
        ("moveTo", [(36, 98)]), ("lineTo", [(104, 98)]), ("qCurveTo", [(134, 98), (134, 64)]),
        ("qCurveTo", [(134, 30), (104, 30)]), ("lineTo", [(36, 30)]), ("closePath", []),
    ], 170),
    "C": ([
        ("moveTo", [(165, 45)]), ("qCurveTo", [(140, 0), (92, 0)]), ("qCurveTo", [(0, 0), (0, 112)]),
        ("qCurveTo", [(0, 225), (92, 225)]), ("qCurveTo", [(140, 225), (165, 180)]), ("lineTo", [(131, 162)]),
        ("qCurveTo", [(117, 190), (92, 190)]), ("qCurveTo", [(38, 190), (38, 112)]),
        ("qCurveTo", [(38, 35), (92, 35)]), ("qCurveTo", [(117, 35), (131, 63)]), ("closePath", []),
    ], 165),
}

GAP = 11


def icon(text, color, path):
    # Lay the letters out left to right, then center the word where Seti centers ASM.
    placed, x = [], 0
    for letter in text:
        if letter in seti:
            ops, left, right = seti[letter]
            placed.append((ops, x - left, 0))
            x += right - left + GAP
        else:
            ops, width = drawn[letter]
            placed.append((ops, x, BASE))
            x += width + GAP
    shift = 500 - (x - GAP) / 2
    svg = SVGPathPen(None)
    for ops, dx, dy in placed:
        # Flip to SVG's y-down coordinates within the 1000-unit em.
        pen = TransformPen(svg, (1, 0, 0, -1, dx + shift, 1000 - dy))
        for op, args in ops:
            getattr(pen, op)(*args)
    # Seti draws its 1000-unit em at 150% of the font size; this view box shows the letters at that size in 16 px.
    content = (
        "<!-- The A, S and M are Seti UI's (https://github.com/jesseweed/seti-ui), MIT licensed, Copyright (c) 2014 "
        "Jesse Weed; see ThirdPartyNotices.txt. -->\n"
        f'<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="90 90 820 820">'
        f'<path fill="{color}" fill-rule="evenodd" d="{svg.getCommands()}"/></svg>\n')
    open(path, "w", newline="\n").write(content)


icon("BAS", "#8DC149", sys.argv[2])
icon("MAC", "#CC3E44", sys.argv[3])
icon("ASM", "#CC3E44", sys.argv[4])
print("ok")
