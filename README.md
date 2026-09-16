# librivoxmerge
Merges librivox audiobook zip archives (https://librivox.org/) into a single audio file.

    Usage:
     librivoxmerge.sh [options] mp3 <archive.zip> - single MP3
     librivoxmerge.sh [options] m4a <archive.zip> - single M4A with chapter markers

    Options:
     -f, --force  Overwrite output file if it already exists
     -h, --help   Show this message

    Merges librivox audiobook zip archives (https://librivox.org/) into a single audio file.

    MP3: wide player support but no chapters. Much faster to generate than M4A.
    M4A: chapter support but requires a compatible player. Much slower to generate than MP3.
     Since the MP3s within a librivox zip archive don't always represent chapters in the
     book, this script labels the contents of each mp3 "Part 1", "Part 2", etc.
     Once the M4A file has been generated, you can manually rename the parts to reflect 
     the book's actual naming structure, e.g: "chapter 2, part 3", or simply use as-is.

