### Snakefile for estimating single-sample heterozygosity using angsd. We
### estimate H for regions of depth 2-4 and 5-8 for each sample. We will end up
### with slightly different precision for each sample at each depth class.

### Set up environment
### Alignment directory has bam files for all sample names in "wgs_sample_list.txt"
	### Naming convention is {sample}.bam
### This snakefile is run using a PBS job submission script which first creates some inputs

HOME_DIR = "/mnt/data/dayhoff/home/u6905905"
SCRATCH = "/mnt/data/dayhoff/home/scratch/groups/mikheyev/LHISI"
READ_DIR = SCRATCH + "/Reads/WGS"
ALN_DIR = SCRATCH + "/Alignments/WGS"
REF_DIR = SCRATCH + "/References"
OUT_DIR = SCRATCH + "/Analysis/SingleSampleHEstimation"
SOFT_DIR = "/mnt/data/dayhoff/home/u6905905/"
ANGSD_DIR = SOFT_DIR + "/angsd"

### Get sample names from list file
### Also make list of scaffolds to consider

# Modify this line to exclude or include scaffolds as necessary
CHROMS = ["CM056993.1","CM056994.1","CM056995.1","CM056996.1","CM056997.1","CM056998.1","CM056999.1","CM057000.1","CM057001.1","CM057002.1","CM057003.1","CM057004.1","CM057005.1","CM057006.1","CM057007.1","CM057008.1"]
#CHROMS = ["CM057008.1"]
depths = ["low","mid"]
samples = [line.strip() for line in open("wgs_sample_list.txt").readlines()]
results_pattern = OUT_DIR + "/{sample}_{depth}Depth_{chrom}.ml"
results = expand(results_pattern,sample=samples,depth=depths,chrom=CHROMS)

### Not sure all of above is necessary since results are actually just a single file....
### To be cleaned up

rule all:
	input: OUT_DIR + "/het_estimates.txt"

### First rule is to get a depth file for all individuals for all scaffolds. It
### creates large temp files, but we remove them at the end of the next rule. It
### is also costly, so we only want to do it once.

rule get_depths:
	input: ALN_DIR + "/{sample}.bam"
	output: OUT_DIR + "/{sample}_{chrom}_depths.pos.gz"
	threads: 12
	params:
		angsd = ANGSD_DIR,
		out = OUT_DIR,
		ref = REF_DIR,
		prefix = "{sample}_{chrom}"
	priority: 1
	shell:
		"""
		{params.angsd}/angsd -uniqueOnly 1 -remove_bads 1 -only_proper_pairs 1 -minMapQ 30 -minQ 30 \
		-doCounts 1 -dumpCounts 1 -minInd 1 -nThreads {threads} \
		-i {input} -out {params.out}/{params.prefix}_depths -r {wildcards.chrom}:1-
		"""

### Rule to take counts of good reads and make region files for angsd. We make
### one for mid (5-8) and one for low (2-4) depth.

rule make_beds:
	input: 
		depthsfile = OUT_DIR + "/{sample}_{chrom}_depths.pos.gz", 
		problematic = REF_DIR + "/problematic_regions.bed", 
		repeats = REF_DIR + "/Annotation/repeats_major.bed"
	output: OUT_DIR + "/{sample}_{depth}Depth_{chrom}_nonRepeat"
	threads: 2
	params:
		angsd = ANGSD_DIR,
		out = OUT_DIR,
		ref = REF_DIR,
		prefix = "{sample}_{depth}Depth_{chrom}"
	priority: 5
	shell:
		"""
		cd {params.out}

		# If statement to get different upper and lower bounds
		DEPTH={wildcards.depth}
		if [ $DEPTH == "low" ]
		then
			UPPER=5
			LOWER=1
		elif [ $DEPTH == "mid" ]
		then
			UPPER=9
			LOWER=4
		fi

		# Turn these counts into a bedfile of sites
		zcat {input.depthsfile} | \
		awk -v LOWER=$LOWER -v UPPER=$UPPER \
		'$3 > LOWER && $3 < UPPER {{print $1"\t"$2-1"\t"$2}}' > tmp1_{params.prefix}

		# Merge these intervals
		bedtools merge -i tmp1_{params.prefix} > tmp2_{params.prefix}

		# Remove anything repetitive
		bedtools subtract -a tmp2_{params.prefix} -b {input.repeats} > tmp3_{params.prefix}

		# Remove anything problematic identified by ngsParalog
		bedtools subtract -a tmp3_{params.prefix} -b {input.problematic} | \
		awk '{{print $1"\t"$2+1"\t"$3+1}}' > {params.prefix}_nonRepeat

		# Sleep for a couple of seconds
		sleep 3s

		# Now index
		{params.angsd}/angsd sites index {params.prefix}_nonRepeat
		touch {params.prefix}_nonRepeat.*

		# Remove tmp files
		rm tmp1_{params.prefix} tmp2_{params.prefix} tmp3_{params.prefix}
		"""

# Rule to remove depths file now that it's been used; it takes up way too much
# space. The rule makes fake outputs in order to force the DAG through this
# before moving on to actual parameter estimation. Priority is set to high so
# that once a pos file is made, it gets quickly processed then removed before
# other depth files get created.

rule remove:
	input:
		OUT_DIR + "/{sample}_lowDepth_{chrom}_nonRepeat",
		OUT_DIR + "/{sample}_midDepth_{chrom}_nonRepeat"
	output:
		out1 = OUT_DIR + "/{sample}_lowDepth_{chrom}_check",
		out2 = OUT_DIR + "/{sample}_midDepth_{chrom}_check"
	params:
		out = OUT_DIR
	priority: 10
	shell:
		"""
		rm {params.out}/{wildcards.sample}_{wildcards.chrom}_depths.pos.gz
		touch {output.out1} {output.out2}
		"""

### Rule to estimate sample allele frequencies per site. We do this per sample
### per depth class per scaffold.

rule do_saf:
	input:
		in1 = OUT_DIR + "/{sample}_lowDepth_{chrom}_check",
		in2 = OUT_DIR + "/{sample}_midDepth_{chrom}_check",
		sites = OUT_DIR + "/{sample}_{depth}Depth_{chrom}_nonRepeat",
		bam = ALN_DIR + "/{sample}.bam",
		ref = REF_DIR + "/LHISI_Scaffold_Assembly.fasta"
	output: OUT_DIR + "/{sample}_{depth}Depth_{chrom}.saf.idx"
	threads: 10
	params:
		angsd = ANGSD_DIR,
		out = OUT_DIR,
		prefix = "{sample}_{depth}Depth_{chrom}"
	priority: 1
	shell:
		"""
		{params.angsd}/angsd -i {input.bam} -anc {input.ref} -ref {input.ref} -out {params.out}/{params.prefix} -nThreads {threads}  \
		-uniqueOnly 1 -remove_bads 1 -only_proper_pairs 1 -trim 0 -C 50 -baq 1 -minMapQ 30 -minQ 30 \
		-doSaf 1 -GL 2 -sites {input.sites} 2> {params.out}/{params.prefix}_saf.err -r {wildcards.chrom}:1-
		"""

### Rule to estimate single sample SFS. We do this per sample per depth class
### per scaffold.

rule ml_est:
	input: OUT_DIR + "/{sample}_{depth}Depth_{chrom}.saf.idx"
	output: OUT_DIR + "/{sample}_{depth}Depth_{chrom}.ml"
	threads: 10
	params:
		angsd = ANGSD_DIR,
		out = OUT_DIR,
		prefix = "{sample}_{depth}Depth_{chrom}"
	priority: 1
	shell:
		"""
		{params.angsd}/misc/realSFS -P {threads} -fold 1 -maxIter 5000 {input} > {output} 2> {params.out}/{params.prefix}_ml.err
		rm {params.out}/{params.prefix}.saf.idx {params.out}/{params.prefix}.saf.pos.gz {params.out}/{params.prefix}.saf.gz
		"""

### Rule to make a table. Takes all previous outputs and loops over the samples,
### scaffolds, and depth classes to calculate H and make a long-format table.

rule collate_and_tar:
	input: results
	output: OUT_DIR + "/het_estimates.txt"
	params:
		chroms = expand("{chrom}",chrom=CHROMS),
		samples = expand("{sample}",sample=samples),
		depths = expand("{depth}",depth=depths),
		out = OUT_DIR
	threads: 1
	shell:
		"""
		cd {params.out}
		DATE=$(date '+%d%m%Y_%H%M%S')

		# Add header to output file
		echo -e "Sample\tChrom\tDepth\tHet\tSites" > het_estimates_${{DATE}}.txt

		# Loop over scaffolds, samples, and depths
		for chrom in {params.chroms}
			do
			for sample in {params.samples}
				do
				for depth in {params.depths}
					do

						# Get stats
						stats=$(awk '{{print $2/($2+$1)"\t"$1+$2}}' ${{sample}}_${{depth}}Depth_${{chrom}}.ml)

						# Print out the stats into table row
						echo -e "${{sample}}\t${{chrom}}\t${{depth}}\t${{stats}}" >> het_estimates_${{DATE}}.txt

					done
				done
			done

		# Tar other output files
		tar -cvzf SingleSampleH_${{DATE}}.tar.gz *err *Repeat
		rm *err *Repeat *arg *check *ml *bin *idx

		# Make final output file to ensure that snakemake closes without error
		cat het_estimates_${{DATE}}.txt > {output}
		"""
