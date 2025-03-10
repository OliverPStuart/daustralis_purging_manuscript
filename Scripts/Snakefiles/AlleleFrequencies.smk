### Snakefile for estimating allele frequencies for all individuals. We first
### estimate allele frequencies for all individuals combined, one scaffold at a
### time. Then we take those and estimate the allele frequencies within the
### three populations, specifying the reference allele as the ancestral. The aim
### is to find mutually fixed alleles in the different populations.

### Do LHISI and LHIP have different fixed alleles? Where are those alleles?
### Do LHISI and LHIP retain many alleles segregating in WILD?

### Set up environment

HOME_DIR = "/mnt/data/dayhoff/home/scratch/groups/mikheyev/LHISI"
READ_DIR = HOME_DIR + "/Reads/WGS"
ALN_DIR = HOME_DIR + "/Alignments/WGS"
REF_DIR = HOME_DIR + "/References"
OUT_DIR = HOME_DIR + "/Analysis/AlleleFrequencies"
SOFT_DIR = "/mnt/data/dayhoff/home/u6905905/"
ANGSD_DIR = SOFT_DIR + "/angsd"

### Make list of populations to consider, then expand into a results pattern.
### Each pop in pops corresponds to a "{population}_bam_list.txt" file which is created
### in the PBS job prior to running this Snakefile. There is also a file for
### all individuals "all_bam_list.txt" which is used as input to the first
### rule, but we don't need to specify that.

pops = ["wild","lhip","lhisi"]
results_pattern = OUT_DIR + "/{population}.mafs.gz"
results = expand(results_pattern,population=pops)

### Also make scaffold vector

CHROMS = ["CM056993.1","CM056994.1","CM056995.1","CM056996.1","CM056997.1","CM056998.1","CM056999.1","CM057000.1","CM057001.1","CM057002.1","CM057003.1","CM057004.1","CM057005.1","CM057006.1","CM057007.1","CM057008.1"]
# Tester line
#CHROMS = ["CM057007.1","CM057008.1"]

rule all:
	input: results

### Rule to make the whole-genome mask for later. Sleep + touch is used to make
### *.idx/*.bin files look older than the sites file, since angsd does some
### funny rewriting there.

rule make_mask:
  input:
    bed = REF_DIR + "/autosome_regions.bed",
    mask = REF_DIR + "/Annotation/repeats_major.bed"
  output: OUT_DIR + "/autosome_regions_masked"
  threads: 8
  params:
    angsd = ANGSD_DIR,
    out = OUT_DIR
  shell:
    """
    cd {params.out}

    # Mask region file for angsd which is 1-indexed
    bedtools subtract -a {input.bed} -b {input.mask} | \
    awk '{{print $1"\t"$2+1"\t"$3+1}}' > {output}

    # Now index it with angsd
    {params.angsd}/angsd sites index {output}
    sleep 10s
    touch {output}.bin {output}.idx
    """

### Rule to estimate mafs for all individuals at once. Important thing here is
### the various read filters, "-doMajorMinor 4". This sets major/minor relative
### to the reference base which makes identifying fixed differences possible.
### This is done per scaffold. We do NOT filter on minor allele frequency yet,
### we do that later as part of the analysis proper. We use a pretty middling
### p-value cutoff for the SNP identification, since we don't have tons of
### individuals.

rule estimate_all:
  input:
    list = HOME_DIR + "/all_bam_list.txt",
    ref = REF_DIR + "/LHISI_Scaffold_Assembly.fasta",
    mask = OUT_DIR + "/autosome_regions_masked"
  output:
    OUT_DIR + "/{scaffold}_all.mafs.gz"
  threads: 8
  params:
    angsd = ANGSD_DIR,
    out = OUT_DIR,
    prefix = "{scaffold}_all"
  resources: mem_mb=12000
  shell:
    """
    # Order of angsd lines is:
      # File input/output
      # Read filters
      # Sample filters
      # Subroutines invoked
      # Masks

    {params.angsd}/angsd -b {input.list} -ref {input.ref} -out {params.out}/{params.prefix} \
    -uniqueOnly 1 -remove_bads 1 -only_proper_pairs 1 -trim 0 -C 50 -baq 1 -minMapQ 30 -minQ 30 \
    -SNP_pval 1e-4 -minInd 9 -setMinDepthInd 2 -setMaxDepthInd 8 \
    -doCounts 1 -GL 2 -doMaf 1 -doMajorMinor 4 -nThreads {threads} \
    -sites {input.mask} -r {wildcards.scaffold}:1-
    """

### Rule to get lists of sites from each scaffold and index them for angsd. This
### is done per scaffold. Sleep + touch is used to make *.idx/*.bin files look
### older than the sites file, since angsd does some funny rewriting there.

rule make_sites:
  input: OUT_DIR + "/{chrom}_all.mafs.gz"
  output: OUT_DIR + "/{chrom}_sites"
  threads: 2
  params:
    angsd = ANGSD_DIR,
    out = OUT_DIR
  shell:
    """
    # Print sites with allele information
    zcat {input} | awk 'NR > 1' | cut -f1,2,3,4 > {output}

    # Now index sites
    {params.angsd}/angsd sites index {output}
    sleep 10s
    touch {output}.bin {output}.idx
    """

### Rule to estimate mafs for all sites for each population.  This is done per
### scaffold per population.

rule estimate_pops:
  input:
    sites = OUT_DIR + "/{scaffold}_sites",
    ref = REF_DIR + "/LHISI_Scaffold_Assembly.fasta",
    list = HOME_DIR + "/{population,[a-z]+}_bam_list.txt"
  output: OUT_DIR + "/{population,[a-z]+}_{scaffold}.mafs.gz"
  threads: 8
  params:
    angsd = ANGSD_DIR,
    out = OUT_DIR,
    prefix = "{population,[a-z]+}_{scaffold}"
  resources:  mem_mb=12000
  shell:
    """
    # Order of angsd lines is:
      # File input/output
      # Read filters
      # Sample filters
      # Subroutines invoked
      # Masks

    # If statement to catch different populations minInd clauses
    POP={wildcards.population}
    if [ $POP == "wild" ]
    then
      MININD=2
      MIN=1
      MAX=5
    elif [ $POP == "lhisi" ]
    then
      MININD=4
      MIN=2
      MAX=8
    elif [ $POP == "lhip" ]
    then
      MININD=4
      MIN=2
      MAX=8
    fi

    {params.angsd}/angsd -b {input.list} -ref {input.ref} -out {params.out}/{params.prefix} \
    -uniqueOnly 1 -remove_bads 1 -only_proper_pairs 1 -trim 0 -C 50 -baq 1 -minMapQ 30 -minQ 30 \
    -minInd $MININD -setMinDepthInd $MIN -setMaxDepthInd $MAX \
    -doCounts 1 -GL 2 -doMaf 1 -doMajorMinor 4 -nThreads {threads} \
    -sites {input.sites} -r {wildcards.scaffold}:1-
    """

### Rule to combine all files per population. We wait until all a population's
### analyses have finished running and then loop through the scaffolds to make
### one output file per population with minor allele frequencies.

rule combine:
  input: expand(OUT_DIR + "/{{population}}_{chrom}.mafs.gz",population=pops,chrom=CHROMS)
  output: OUT_DIR + "/{population,[a-z]+}.mafs.gz"
  threads: 1
  params:
    angsd = ANGSD_DIR,
    out = OUT_DIR,
    scafs = CHROMS
  shell:
    """
    cd {params.out}

    # Make header
    echo -e "chromo\tposition\tmajor\tminor\tref\tknownEM\tnInd" > {wildcards.population}.mafs

    # Now loop over scaffold outfiles
    for scaf in {params.scafs}
      do

      # Take all lines except the header
      zcat {wildcards.population}_${{scaf}}.mafs.gz | awk 'NR > 1' >> {wildcards.population}.mafs

      done

      # Compress the table
      gzip {wildcards.population}.mafs

			# Remove temporary outputs
			rm {wildcards.population}*CM*maf* {wildcards.population}_CM*.arg

    """
