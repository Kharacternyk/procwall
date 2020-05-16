#!/bin/bash
BACKGROUND=#073642
EDGE=#b58900
NODE=#dc322f
FONT_COLOR=#eee8d5
FONT_SIZE=10
FONT_NAME=monospace
RANKSEP=1
OUTPUT="$PWD/procwall.png"
STARTDIR="$PWD"

prepare() {
    WORKDIR="$(mktemp -d)"
    cd "${WORKDIR}"
}

cleanup() {
    cd "${STARTDIR}" && rm -rf "${WORKDIR}"
}

generate_graph() {
    DATA="$(ps -U $EUID -o pid,ppid,euid,comm,%mem --noheaders)"
    COLUMN=PID

    for VALUE in $DATA; do
        case $COLUMN in
            PID)
                COLUMN=PPID
                _PID=$VALUE
                ;;
            PPID)
                COLUMN=EUID
                _PPID=$VALUE
                ;;
            EUID)
                COLUMN=COMM
                _EUID=$VALUE
                ;;
            COMM)
                COLUMN=MEM
                _COMM=$VALUE
                ;;
            MEM)
                COLUMN=PID
                _MEM=$(bc <<< "scale=3; $VALUE/30 + 0.15")

                echo "$_PPID -> $_PID;" >> stripped.gv
                echo "$_PID [width=$_MEM, height=$_MEM, xlabel=\"$_COMM\"]" >> stripped.gv
                ;;
        esac
    done
}

compile_graph() {
    # Compile the file in DOT languge.
    # The graph is directed and strict (doesn't contain any edge duplicates).
    echo 'strict digraph G {' > procwall.gv
    cat stripped.gv >> procwall.gv
    echo '}' >> procwall.gv
}

use_wal_colors() {
    if [[ ! -f ~/.cache/wal/colors ]]; then
        echo 'Run pywal first'
        exit 1
    fi

    echo 'Using pywal colors:'

    # change `n` in `head -n` to use the n-th terminal color set by pywal
    # you can preview these colors in ~/.cache/wal/colors.json
    BACKGROUND=$(head < ~/.cache/wal/colors -1 | tail -1)
    EDGE=$(head < ~/.cache/wal/colors  -4 | tail -1)
    NODE=$(head < ~/.cache/wal/colors  -2 | tail -1)
    FONT_COLOR=$(head < ~/.cache/wal/colors  -8 | tail -1)

    echo "    Background:    ${BACKGROUND}ff"
    echo "    Edge:          $EDGE"
    echo "    Node:          $NODE"
}

render_graph() {
    # Style the graph according to preferences.
    declare -a twopi_args=(
        '-Tpng' 'procwall.gv'
        "-Gbgcolor=${BACKGROUND}"
        "-Granksep=${RANKSEP}"
        "-Ecolor=${EDGE}"
        "-Ncolor=${NODE}"
        "-Nfontcolor=${FONT_COLOR}"
        "-Nfontsize=${FONT_SIZE}"
        "-Nfontname=${FONT_NAME}"
        "-Nstyle=filled"
        "-Nshape=point"
        '-Nheight=0.3'
        '-Nwidth=0.3'
        '-Earrowhead=normal'
    )

    # Optional arguments
    [[ -n $ROOT ]] && twopi_args+=("-Groot=${ROOT}")

    twopi "${twopi_args[@]}" > procwall.png
}

set_wallpaper() {
    set +e

    if [[ -n $DE_INTEGRATION ]]; then
        if [[ -z $SCREEN_SIZE ]]; then
            SCREEN_SIZE=$(
                xdpyinfo | grep dimensions | sed -r 's/^[^0-9]*([0-9]+x[0-9]+).*$/\1/'
            )
        fi
        convert procwall.png \
            -gravity center \
            -background "${BACKGROUND}" \
            -extent "${SCREEN_SIZE}" \
            "${OUTPUT}"
        copy_to_xdg

        #Write xml so that file is recognised in gnome-control-center
        mkdir -p "${XDG_DATA_HOME}/gnome-background-properties"
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <!DOCTYPE wallpapers SYSTEM \"gnome-wp-list.dtd\">
        <wallpapers>
	        <wallpaper deleted=\"false\">
		           <name>procwall${BACKGROUND}</name>
		           <filename>${XDGOUT}</filename>
	        </wallpaper>
        </wallpapers>" \
            > "${XDG_DATA_HOME}/gnome-background-properties/procwall${BACKGROUND}.xml"

        hsetroot -solid "$BACKGROUND"-full "${XDGOUT}" \
            2> /dev/null && echo 'Using hsetroot to set the wallpaper'

        feh --bg-center --no-fehbg --image-bg "$BACKGROUND" "${XDGOUT}" \
            2> /dev/null && echo 'Using feh to set the wallpaper'

        gsettings set org.gnome.desktop.background picture-uri "${XDGOUT}" \
            2> /dev/null && echo 'Using gsettings to set the wallpaper'

    else
        hsetroot -solid "$BACKGROUND" -full "${OUTPUT}" \
            2> /dev/null && echo 'Using hsetroot to set the wallpaper'

        feh --bg-center --no-fehbg --image-bg "$BACKGROUND" "${OUTPUT}" \
            2> /dev/null && echo 'Using feh to set the wallpaper'
    fi

    set -e
}

copy_to_xdg() {
    #Copy the output to $HOME/.local/share/wallpapers as it is a standard XDG Directory
    #This will make the wallpapers visible in KDE settings (and maybe WMs if they have a setting)
    mkdir -p "${XDG_DATA_HOME}/wallpapers/procwall"
    cp "${OUTPUT}" "${XDGOUT}"
}

main() {
    prepare

    if [[ -n $PYWAL_INTEGRATION ]]; then
        use_wal_colors
    fi

    generate_graph

    compile_graph

    render_graph

    cp "${WORKDIR}/procwall.png" "${OUTPUT}"

    if [[ -z $IMAGE_ONLY ]]; then
        set_wallpaper
    fi

    cleanup

    echo "The image has been put to ${OUTPUT}"
}

help() {
    echo "USAGE: $0
        [ -iDW ]
        [ -b BACKGROUND_COLOR ]
        [ -s EDGE_COLOR ]
        [ -d NODE_COLOR ]
        [ -x NODE_OWNED_BY_ROOT_COLOR ]
        [ -c ROOT ]
        [ -r RANKSEP ]
        [ -o OUTPUT ]
        [ -S SCREEN_SIZE ]

        Use -i to suppress wallpaper setting.
        Use -D to enable integration with desktop environments.
        Use -W to enable pywal integration.

        All colors may be specified either as
        - a color name (black, darkorange, ...)
        - a value of format #RRGGBB
        - a value of format #RRGGBBAA

        ROOT is the package that will be put in the center of the graph.
        RANKSEP is the distance in **inches** between the concentric circles.
        OUTPUT is the path where the generated image is put.
        SCREEN_SIZE makes sense to set only if -D is enabled and you're on Wayland.
        "

    exit 0
}

options='hiDWb:s:d:c:r:o:S:'
while getopts $options option; do
    case $option in
        h) help ;;
        i) IMAGE_ONLY=TRUE ;;
        D) DE_INTEGRATION=TRUE ;;
        W) PYWAL_INTEGRATION=TRUE ;;
        b) BACKGROUND=${OPTARG} ;;
        s) EDGE=${OPTARG} ;;
        d) NODE=${OPTARG} ;;
        c) ROOT=${OPTARG} ;;
        r) RANKSEP=${OPTARG} ;;
        o) OUTPUT=${OPTARG} ;;
        S) SCREEN_SIZE=${OPTARG} ;;
        \?)
            echo "Unknown option: -${OPTARG}" >&2
            exit 1
            ;;
        :)
            echo "Missing option argument for -${OPTARG}" >&2
            exit 1
            ;;
        *)
            echo "Unimplemented option: -${OPTARG}" >&2
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ -z $XDG_DATA_HOME ]]; then
    XDG_DATA_HOME=~/.local/share
fi
XDGOUT="${XDG_DATA_HOME}/wallpapers/procwall/procwall${BACKGROUND}.png"

main "$@"
