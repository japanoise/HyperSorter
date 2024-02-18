#!/bin/bash
die() {
    echo "release failed: $1" >&2
    exit 1
}

version=v1.0.0
raco=raco
progname=hypersorter
reldir=release
artifact="$reldir"/"$progname"-"$OSTYPE"-"$(uname -m)"-"$version"
mainfile="$progname".rkt

ext=""
case "$OSTYPE" in
    msys* )
        echo "Detected msys - using .exe & absolute path"
        ext=".exe"
        raco=/c/'Program Files'/Racket/raco;;
    cygwin* )
        echo "Detected cygwin - using .exe"
        echo "Make sure raco is on your PATH"
        ext=".exe";;
    *)
        echo "Not using an extension";;
esac

mkdir -pv "$reldir"

echo "$raco" exe "$mainfile"
"$raco" exe "$mainfile" || die "compilation error"

echo "$raco" distribute "$artifact" "$progname""$ext"
"$raco" distribute "$artifact" "$progname""$ext" || die "raco distribute error"

if [ "$ext" = ".exe" ]
then
    # Windows users expect zip files
    zip -r "$artifact".zip "$artifact" && echo "$artifact".zip created
else
    # Everybody else can deal with tar.gz
    tar cvzf "$artifact".tar.gz "$artifact" && echo "$artifact".tar.gz created
fi
