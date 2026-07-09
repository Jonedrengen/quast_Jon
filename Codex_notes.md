

PASS if:
  total_length between 4.3e6 and 6.2e6
  GC between 49.5 and 51.5
  contigs >=500 bp <=300
  N50 >=50000
  Ns per 100 kbp near 0
  duplication_ratio <=1.05
  genome_fraction >=95, if using a close reference

generate a tsv file,
rows: ids
columns: parameters for passing. (e.g. GC : PASSED, N50 : FAILED)

Note: I have a conda env with all needed dependencies: /opt/anaconda3/envs/quast_JOSS

