# splitpages
Shell script that divides selected pdf pages in half from top to bottom.

Only compatible with macOS for now. The script automatically selects the active pdf in the pdf application that you enter in the script itself. If you're using Adobe Acrobat, the script will close and reopen the original pdf so that you can review the changes. 

Note that the dialog at the beginning requires you to enter page ranges in the form x-x, where "x" is a single, whole, real, indo-arabic number (i.e., you can't enter cpdf page range syntactical units such as "end" or "1-~1"). Separate ranges by a comma followed by a single space, if you want to enter multiple ranges. If a range is a single page, enter it as x-x. All page ranges must contain all/only pages that will be split.

The script requires [cpdf](https://coherentpdf.com/) and [cliclick](https://github.com/BlueM/cliclick) to work. Both can be installed (for free) using Homebrew or Macports.
