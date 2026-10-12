# Slides

Decks live here instead of Overleaf so that every figure on a slide traces back to
the script in this repo that produced it.

```
slides/
  RDDs-Inframarginal/
    main.tex        # 70 frames: RDD threshold-crossing + inframarginal designs
```

## The path convention

Slides reference figures directly from `output/`, with a relative path from the deck's
own directory:

```latex
\includegraphics[width=\linewidth]{../../output/figures/Enrolls/rd_enrolls_uni.pdf}
\includegraphics[width=0.49\textwidth]{../../output/sua_kernelden_event_study_broad_area.png}
```

There is no `\graphicspath` and no copy of the figures under `slides/`. A path in the
deck is the path Stata wrote to, so `grep` finds the producing script:

```bash
grep -rn "sua_kernelden_event_study_broad_area" code/
```

**Do not put spaces in figure paths** — `graphicx` handles them badly. Use underscores.

## Adding a new result

1. Have the estimation script `graph export` into `$output` (or a subdirectory of it),
   exactly as the existing scripts do:

   ```stata
   graph export "$output/sua_kernelden_event_study_broad_area.png", replace width(2400)
   ```

2. Run the script, then pull the figure back from the server if it ran there:

   ```bash
   rsync -avz jrodriguezo@192.168.20.25:/home/jrodriguezo/majors/output/ output/
   ```

3. Reference it in the deck with its `../../output/...` path.

## Building

```bash
cd slides/RDDs-Inframarginal
latexmk -pdf main.tex
```

`latexmk` handles the multiple passes the table of contents needs. Build artifacts and
the compiled PDF are gitignored; the `.tex` plus the figures in `output/` reproduce the
deck.

## Known gap

The 29 tables in `main.tex` are **hardcoded `tabular` blocks**, not `\input` of generated
files — numbers were typed in by hand from Stata output, so they do not update when an
estimation is re-run. `output/tables/` holds a handful of generated `.tex` fragments that
the deck does not currently use. Wiring the tables up the way the figures now are is
worth doing, but it is a separate change.
