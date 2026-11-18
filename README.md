# autogloss

An automatic, page-referenced glossary for LuaLaTeX. You give it a list of
terms; it finds every place they appear in your typeset document and prints
a glossary listing each term with the pages it appears on.

You don't tag anything in your chapters. Write as normal and the package does
the rest.

```
four-top ........................................ 5, 6
GNN
   Graph neural network ......................... 6, 7, 12–15
jet ............................................. 1, 3, 7
large-R jet ..................................... 3
```

---
## AI Disclosure
Entering the final months of my thesis, learning Lua just to make a plugin is not a responsible use of my time. As such, this package is a complete vibe-code. That being said, if you're reading this at all because you *are* writing a thesis in science, then you understand that there is more nuance to AI than all or nothing, and there are appropriate use cases for this technology. This is one of them.

---
## Requirements

- **LuaLaTeX** (Overleaf: *Menu → Settings → Compiler → LuaLaTeX*).
  The package stops with an error under pdfLaTeX or XeLaTeX.
- LaTeX kernel from 2020-10 or newer (any TeX Live from 2021 on).

## Installation

Put both files in the **top level** of your project, next to `main.tex`:

```
main.tex
autogloss.sty
autogloss.lua
chapters/...
```

Both files must be in the top level. The `.sty` loads the `.lua`, and it
won't find it in a subfolder.

---

## Quick start

```latex
\usepackage{hyperref}          % optional; load before autogloss
\usepackage{autogloss}

\autoglossterms{jet, large-$R$ jet, four-top, Monte Carlo, $\eta$-intercalibration}
\autoglossterm[desc={Graph neural network},
               alias={graph neural network, graph network}]{GNN}

\begin{document}
...
\mainmatter
\include{chapters/intro}
...
\printautoglossary
\end{document}
```

Compile as usual. Overleaf (latexmk) runs as many passes as needed for the
page numbers to settle.

---

## Declaring terms

### Several plain terms

```latex
\autoglossterms{jet, four-top, Monte Carlo}
```

### One term with options

```latex
\autoglossterm[<options>]{<term>}
```

| Option     | Meaning |
|------------|---------|
| `desc={…}`    | A description, printed on its own indented line(s) under the term. |
| `alias={…}`   | Other spellings that count as the same entry, comma-separated. Keep the braces. Wrap an alias that contains a comma in its own braces: `alias={{jets, large-R}, fat jet}`. |
| `display={…}` | What to print as the entry name, if different from the term itself. |

Declare terms in the preamble. A term declared partway through the document
only matches text after that point.

Declaring the same term twice merges the two declarations, so you can add
aliases or a description later.

### How matching works

- **Case-insensitive** by default: "Jet" at the start of a sentence counts.
- **Whole words only**: `jet` does not match "Jetty" or "projet".
- **Plurals** are caught automatically: `jet` matches "jets",
  `GNN` matches "GNNs".
- **Multi-word terms** match across line breaks and `~`.
- **Hyphens** are fine: `four-top`, `pile-up`.
- **Math in terms** works for simple cases. Write the term the way you write it
  in the text: `large-$R$ jet`, `$\eta$-intercalibration`. Greek letters
  (`\eta`, `\Delta`, …) and single letters in math are understood. More
  complicated math (subscripts, `\mathrm{…}`) won't match.
- **Ligatures** ("fi", "ff", …) are handled.

### Where it looks

Counted: body text, chapter and section titles, footnotes, figure and table
captions, table cells.

Not counted: running headers and footers, the table of contents, list of
figures/tables, and the glossary itself.

---

## Placing the glossary

```latex
\printautoglossary
```

This starts a new unnumbered chapter (or section, in classes without
chapters), titled "Glossary". It adds a table-of-contents entry and switches
scanning off.

I didn't name this command `\glossary` because LaTeX already defines
`\glossary`. If you really want that name and don't use the `glossaries`
package:

```latex
\let\glossary\printautoglossary
```

---

## What gets scanned

By default, scanning:

- **starts** at `\mainmatter`, or at your first numbered `\chapter` if you
  don't use `\mainmatter`. Chapters in `\frontmatter` (abstract,
  acknowledgements) are never scanned;
- **stops** at `\backmatter` or at `\printautoglossary`, whichever comes first.

You can control it yourself anywhere in the document:

```latex
\autoglossstart     % begin counting from here
\autoglossstop      % stop counting from here
```

**Bibliography:** if your bibliography comes *before* the glossary and isn't
in `\backmatter`, stop scanning first, or words in paper titles get counted:

```latex
\autoglossstop
\printbibliography
```

---

## Package options

```latex
\usepackage[title=Index of Terms, noranges]{autogloss}
```

| Option          | Effect |
|-----------------|--------|
| `title=…`       | Heading of the glossary (default `Glossary`). |
| `casesensitive` | "Jet" and "jet" become different. Applies to every term. |
| `noplurals`     | Don't match a trailing *s* / *es*. |
| `noranges`      | Print `5, 6, 7` instead of `5–7`. |
| `inputorder`    | List terms in the order you declared them, not alphabetically. |
| `notoc`         | No table-of-contents entry for the glossary. |
| `nolinks`       | Don't hyperlink page numbers (they link automatically if `hyperref` is loaded). |
| `maxpagewidth=…` | Fix the width of the page-number block, e.g. `maxpagewidth=0.4\linewidth` or `maxpagewidth=7cm`. Turns off automatic balancing (see *Layout of long entries*). Leave it unset to let the package choose. |
| `manualstart`   | Disable the automatic start/stop. Use `\autoglossstart` / `\autoglossstop` yourself. |

---

## Customising the look

### Layout of long entries

A term with no description goes on one line, with dots leading to the page
numbers. A term with a description gets a line of its own, and the
description goes underneath, indented:

```
four-top ................................................ 5, 6
GNN
   Graph neural network ................................. 6, 7
```

If the description and page numbers don't fit on one line, they split into
two blocks side by side, and both wrap:

```
Jet
   Assuming, of course, that there is   24, 25, 27–41, 43–45, 47, 48,
   such a thing... ..................   53–56, 58–61, 65, 66, 69
```

How the width is split between the two blocks depends on `maxpagewidth`:

- **Not set (default): automatic.** The package tries a range of split
  points and keeps the one that makes the entry the fewest lines tall, which
  usually leaves the two blocks the same height. When several splits are
  equally tall, it gives the description as much width as possible. The
  description column is never narrower than `\autoglossmindescwidth`
  (35% of the line), or its full length if that is shorter, so it isn't
  squeezed into a thin column to save a line.
- **Set: fixed.** The page-number block is always exactly `maxpagewidth` wide,
  or narrower if the whole list fits in less. The description gets the rest.
  Entries also wrap whenever their page list is wider than `maxpagewidth`.
  Use this if you want every wrapped entry's page numbers in one tidy column.

If the description ends up longer, the dots lead into the last line of page
numbers; otherwise the blocks align at the top. Page ranges like `27–41` are
never broken across lines.

### Commands

Redefine any of these after loading the package:

```latex
\renewcommand\autoglosstermfont{\bfseries}   % font for the term
\renewcommand\autoglosspagesep{, }           % between pages
\renewcommand\autoglossrangesep{--}          % inside a range, e.g. 5–7
\renewcommand\autoglossnotfound{\textbf{??}} % shown when no pages are found
\renewcommand\autoglossgap{0.5em}            % space between the two blocks of a wrapped entry
\renewcommand\autoglossdescindent{1.5em}     % indent of the description under its term
\renewcommand\autoglossmindescwidth{0.35\linewidth} % narrowest description column (automatic mode)
```

Page ranges are used for three or more consecutive pages.
Two consecutive pages print as `5, 6`.

---

## Troubleshooting

**An entry shows `??`**
After a full compile this means the term was never found in the scanned
region. Check the spelling, or add an `alias`. The log has a warning naming
each such term:

```
Package autogloss Warning: Term `neverused' has no recorded pages yet
```

`??` also appears on the very first compile, before any page data exists.
That's normal and clears on the next pass.

**"Glossary page numbers changed. Rerun to get them right"**
Overleaf normally reruns automatically. If it doesn't, hit *Recompile* again.

**"autogloss needs LuaLaTeX"**
Switch the compiler (see *Requirements*).

**`Recompile from scratch`**
This clears the stored page data, so the next compile needs one extra pass to
fill the numbers back in.

**A word is counted on a page where it only appears in the header**
It shouldn't be. Headers are excluded. If you see this, it's a bug.

**Front matter or bibliography pages appear in the list**
See *What gets scanned*. Use `\autoglossstop` before that section.

---

## How it works

1. While LuaLaTeX typesets each paragraph and box, a Lua callback reads the
   actual typeset characters (after hyphenation and ligatures). It looks for
   your terms and drops an invisible marker in front of each match.
2. When a page is shipped out to the PDF, each marker on it records that
   page's number. That means the page number is wherever the word really
   lands, after floats move and paragraphs break across pages.
3. At the end of the run the results are written to the `.aux` file.
   `\printautoglossary` prints the results from the *previous* run, which is
   why a change can take one extra compile to show up.

Running headers are built while LaTeX assembles a page, and the scanner skips
that stage. That's how headers are excluded.

**Compile-time cost:** on a 114-page text-only test with 30 terms, about
0.07 s extra per pass (~8%). On a real thesis with figures and a
bibliography it's negligible.

---

## Files

| File            | Contents |
|-----------------|----------|
| `autogloss.sty` | LaTeX interface: options, commands, hooks, layout. |
| `autogloss.lua` | Scanner, matching, page recording, sorting and output. |
