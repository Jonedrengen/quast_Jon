#!/bin/bash
set -euo pipefail

#SAMPLELIST
samplelist_input="$1"
array_output="${2:-}"

if [[ -z "$array_output" ]]; then
    samplelist_filename="$(basename "${samplelist_input%.*}")"
    array_output="${samplelist_filename}_SLURM-ARRAY-READY.txt"
fi

if [[ ! -f "$samplelist_input" ]]; then
    echo "found no sample list: $samplelist_input"
    exit 1
fi

#SLURM_ARRAY SPECIFICATIONS (max size, batch index and job index)
slurm_array_maxsize=1000
i=0
j=1

> "$array_output"

while read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    filename="$line"
    basename_only="$(basename "$filename")"
    sample_id="${basename_only%.gz}"
    sample_id="${sample_id%.fasta}"
    sample_id="${sample_id%.fa}"
    sample_id="${sample_id%.fna}"

    case "$basename_only" in
        *.fasta|*.fa|*.fna|*.fasta.gz|*.fa.gz|*.fna.gz)
            echo "${i}__@__${j}__@__${sample_id}__@__${filename}" >> "$array_output"
            ;;
        *)
            echo "Skipping non-FASTA entry: $line"
            continue
            ;;
    esac

    if [[ $j -lt $slurm_array_maxsize ]]; then
        ((j+=1))
    else
        ((i+=1))
        j=1
    fi
done < "$samplelist_input"

echo "created $(wc -l < "$array_output") QUAST array entries in $array_output"
