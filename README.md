# HyperSorter - visual image sorting

HyperSorter is a program that sorts images visually, one at a time.  It displays
an image in a directory of unsorted images, and gives you a list of directories.
You can click the button to sort the image into the given directory, or type the
name of the directory (with tab completion), and the program will move the file
to the given directory. You can also skip the image to come back to later, and
create new directories in the target directory.

The use case is, for example, when you save a bunch of pictures without care to
whether they're e.g. cat pictures, memes, anime girls, or recipes, and you want
to move them all to a new directory. It's generally assumed that the target
directory (i.e. the directory that contains the subdirectories to which you wish
to sort your files) contains in it a directory of unsorted images (I usually
call this one "sortme"):

* `/home/anon/Pictures`
  - `/home/anon/Pictures/sortme`

But you can equally sort pictures which are saved within the target directory
itself, or in a whole different directory altogether.

When you start the program, you'll see a blank canvas. Go to
`File -> New Directory` or `Directory -> Manage Directories` to load in your
target directory and unsorted images. Once a directory is loaded, you'll see the
current image in the main area of the window, and a status bar at the bottom of
the window which will tell you how many images you've sorted and how many are
remaining to be sorted. Click on a button on the left to sort the image into the
given subdirectory. You can also, while the main window has keyboard focus, type
in the name of the subdirectory you wish to sort to. You don't have to type the
whole thing - just type the first part, and you can press return to send it to
the directory straight away. If there's multiple options displayed, you can
press tab to cycle through them.

The main image window can be scrolled up and down with the scroll wheel or left
to right by scrolling and pressing shift; you can also zoom in by holding down
control and using the scroll wheel, and you can click and drag to pan the image
in any direction. The program can also be controlled entirely with the
keyboard - see the bindings below.

## Keybindings

I have tried to make HyperSorter as accessible as possible. The program can be
used entirely with the keyboard - this was an explicit design goal. However,
Racket's support for accessibility measures is far from there:

- [Five-year-old accessibility issue on
  DrRacket](https://github.com/racket/drracket/issues/219)
- [Very quiet newsgroup discussions on
  accessibility](https://groups.google.com/g/racket-users/c/JTNyF1cR8dQ)
- [A 2020 report on accessibility issues in
  DrRacket](https://www.cameronkleung.com/project/drracket-accessibility)

### General

- Quit the program - `CTRL-Q` or `ALT-F Q`

### Directories

- New directory - `ALT-F N`
- New subdirectory - `ALT-F S`
- Open directory manager - `ALT-D M`
- Switch directory - `ALT-D` then use arrow keys to select the directory, or
  open directory manager (`ALT-D M`) and select directory from the list

### Image Viewer

- Scroll - Arrow keys, or Emacs bindings - `CTRL-P` for up, `CTRL-N` for down,
  `CTRL-B` for left, `CTRL-F` for right.
- Zoom in - `CTRL-+` or `CTRL-=` or `CTRL-.`
- Zoom out - `CTRL--` (Control-minus) or `CTRL-,`
- Reset zoom - `CTRL-0`
- Reset zoom & position - `CTRL-C`

### Subdirectories

**Note: This functionality may need a patch to work with a screenreader.**
Please contact me if you know how to hook custom widgets into the screenreader.
Or, if you use a screenreader and it works for you, please let me know.

- Start typing to show a list of candidates (directories which the program
  thinks match what you're typing)
- Press `TAB` or `CTRL-S` to cycle through the candidates
- Press `ENTER` to sort the image into the current candidate
- Press `CTRL-U` or `CTRL-G` to delete the current search term

## Building

You will need [Racket][racket] (and possibly DrRacket) installed. HyperSorter
has a crunchbang, so on Unix (and maybe MacOS) you can just run the program
directly with `./hypersorter.rkt`, but for a slight speed boost you may want to
compile it as well. HyperSorter was developed with version 8.11.1 of Racket but
did not use any third-party libraries nor any particularly new features, so it
may work with older versions.

[Download Racket][racket] from your distro's repositories or [from its
website][racket].

I will also provide compiled binaries for MacOS and Windows.

[racket]: https://download.racket-lang.org/

## Copying

HyperSorter is copyright (C) japanoise 2024, licensed under the GNU Public
License (GPL) version 3 as published by the Free Software Foundation, or at your
option any later version.
