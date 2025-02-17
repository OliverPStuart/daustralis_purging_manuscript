### Snakefile for calculating genotype likelihoods from WGS data
### The outputs for this are intended for use with RZooROH

### Set up environment

HOME_DIR = "/mnt/data/dayhoff/home/scratch/groups/mikheyev/LHISI"
READ_DIR = HOME_DIR + "/Reads/WGS"
ALN_DIR = HOME_DIR + "/Alignments/WGS"
REF_DIR = HOME_DIR + "/References"
OUT_DIR = HOME_DIR + "/Analysis/GenotypeLikelihoodROH"
SOFT_DIR = "/mnt/data/dayhoff/home/u6905905/"
ANGSD_DIR = SOFT_DIR + "/angsd"

### We do this chromosome by chromosome to speed up the process
### This also makes handling everything easier, as outputs can be quite large
### The output tables, although zipped, have (3 + 3 * samples) columns and (1 + sites) fields

### Specify scaffold indices, expand to names, then fill results vector
CHROMS = ["CM056993.1","CM056994.1","CM056995.1","CM056996.1","CM056997.1","CM056998.1","CM056999.1","CM057000.1","CM057001.1","CM057002.1","CM057003.1","CM057004.1","CM057005.1","CM057006.1","CM057007.1","CM057008.1"]
POPS = ["lhisi", "lhip", "all"]

results_pattern = OUT_DIR + "/{population}_{chrom}.beagle.gz"
results = expand(results_pattern,population=POPS,chrom=CHROMS)

rule all:
	input:
		results

### Rule to make the whole-genome mask for later. Sleep + touch is used to make
### *.idx/*.bin files look older than the sites file, since angsd does some
### funny rewriting there.

rule make_mask:
	input:
		autosome = REF_DIR + "/autosome_regions.bed",
		mask = REF_DIR + "/Annotation/repeats_major.bed",
		problematic = REF_DIR + "/problematic_regions.bed"
	output: OUT_DIR + "/autosome_regions_masked"
	threads: 1
	params:
		angsd = ANGSD_DIR,
		out = OUT_DIR
	shell:
		"""
		cd {params.out}

		# Combine repeat mask and mapping filter
		cat {input.mask} {input.problematic} | \
		sort -k 1,1 -k2,2n | \
		bedtools merge -i stdin > tmp1

		# Subtract this combined mask from the autosomes
		bedtools subtract -a {input.autosome} -b tmp1 | \
		awk '{{print $1"\t"$2+1"\t"$3+1}}' > {output}

		# Now index it with angsd
		{params.angsd}/angsd sites index {output}
		sleep 3s
		touch {output}.*

		rm tmp1
		"""

### Rule to estimate GLs per population per scaffold
### Needs access to a list of bam files to analyse, one per population, lhip, lhisi, wild

rule estimate_gls:
  input:
    list = HOME_DIR + "/{population}_bam_list.txt",
    ref = REF_DIR + "/LHISI_Scaffold_Assembly.fasta",
    mask = OUT_DIR + "/autosome_regions_masked"
  output:
    OUT_DIR + "/{population}_{chrom}.beagle.gz"
  threads: 10
  params:
    angsd = ANGSD_DIR,
    out = OUT_DIR,
    prefix = "{population}_{chrom}"
  shell:
    """

		# Use input list to define minimum number of individuals to consider site
		POP={wildcards.population}
		if [ $POP == "all" ]
		then
			MIN_IND=9
		elif [ $POP == "lhisi" ]
		then
			MIN_IND=4
		elif [ $POP == "lhip" ]
		then
			MIN_IND=4
		fi

		# Order of angsd lines is:
      # File input/output
      # Read filters
      # Sample filters
      # Subroutines invoked
      # Masks

    {params.angsd}/angsd -b {input.list} -ref {input.ref} -out {params.out}/{params.prefix} \
    -uniqueOnly 1 -remove_bads 1 -only_proper_pairs 1 -trim 0 -C 50 -baq 1 -minMapQ 30 -minQ 30 \
    -SNP_pval 1e-4 -minInd $MIN_IND -setMinDepthInd 2 -setMaxDepthInd 8 \
    -doCounts 1 -GL 2 -doGlf 2 -doMaf 1 -doMajorMinor 1 -nThreads {threads} \
    -sites {input.mask} -r {wildcards.chrom}:1- 1> {params.out}/{params.prefix}.out 2> {params.out}/{params.prefix}.err
    """
