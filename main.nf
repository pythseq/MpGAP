#!/usr/bin/env nextflow

/*
                      A docker-based pipeline for generic hybrid, illumina-only
                      or long reads only assembly. It accepts Illumina, ONT and
                      Pacbio data.

                      It uses Unicycler, Flye, Canu or Spades to assemble reads.
                      And uses Nanopolish, VariantCaller or Pilon to polish assemblies.

*/

def helpMessage() {
   log.info """
   Usage:
   nextflow run fmalmeida/MpGAP [--help] [ -c nextflow.config ] [OPTIONS] [-with-report] [-with-trace] [-with-timeline]

   Comments:
   This pipeline contains a massive amount of configuration variables and its usage as CLI parameters would
   cause the command to be huge. Therefore, it is extremely recommended to use the nextflow.config configuration file in order to make
   parameterization easier and more readable.

   Creating a configuration file:
   nextflow run fmalmeida/MpGAP [--get_illumina_config] [--get_ont_config] [--get_pacbio_config]

   Show command line examples:
   nextflow run fmalmeida/MpGAP --show

   Execution Reports:
   nextflow run fmalmeida/MpGAP [ -c nextflow.config ] -with-report
   nextflow run fmalmeida/MpGAP [ -c nextflow.config ] -with-trace
   nextflow run fmalmeida/MpGAP [ -c nextflow.config ] -with-timeline

   OBS: These reports can also be enabled through the configuration file.

   OPTIONS:
            General Parameters - Mandatory

    --outDir <string>                      Output directory name
    --prefix <string>                      Set prefix for output files
    --threads <int>                        Number of threads to use
    --yaml <string>                        Sets path to yaml file containing additional parameters to assemblers.
    --assembly_type <string>               Selects assembly mode: hybrid, illumina-only or longreads-only
    --try_canu                             Execute assembly with Canu. Multiple assemblers can be chosen.
    --try_unicycler                        Execute assembly with Unicycler. Multiple assemblers can be chosen.
    --try_flye                             Execute assembly with Flye. Multiple assemblers can be chosen.
    --try_spades                           Execute assembly with Spades. Multiple assemblers can be chosen.


            Parameters for illumina-only mode. Can be executed by spades and unicycler assemblers.

            Parameters for longreads-only mode. Can be executed by canu, flye and unicycler assemblers.
            In the end, long reads only assemblies can be polished with illumina reads through pilon.

            Parameters for hybrid mode. Can be executed by spades and unicycler assemblers.

   """.stripIndent()
}

def exampleMessage() {
   log.info """
   Example Usages:
      Illumina paired end reads. Since it will always be a pattern match, example "illumina/SRR9847694_{1,2}.fastq.gz",
      it MUST ALWAYS be double quoted as the example below.
./nextflow run fmalmeida/MpGAP --threads 3 --outDir outputs/illumina_paired --run_shortreads_pipeline --shortreads \
"illumina/SRR9847694_{1,2}.fastq.gz" --reads_size 2 --lighter_genomeSize 4600000 --clip_r1 5 --three_prime_clip_r1 5 \
--clip_r2 5 --three_prime_clip_r2 5 --quality_trim 30
      Illumina single end reads. Multiple files at once, using fixed number of bases to be trimmed
      If multiple unpaired reads are given as input at once, pattern MUST be double quoted: "SRR9696*.fastq.gz"
./nextflow run fmalmeida/MpGAP --threads 3 --outDir sample_dataset/outputs/illumina_single --run_shortreads_pipeline \
--shortreads "sample_dataset/illumina/SRR9696*.fastq.gz" --reads_size 1 --lighter_kmer 17 \
--lighter_genomeSize 4600000 --clip_r1 5 --three_prime_clip_r1 5
      ONT reads:
./nextflow run fmalmeida/MpGAP --threads 3 --outDir sample_dataset/outputs/ont --run_longreads_pipeline \
--lreads_type nanopore --longReads sample_dataset/ont/kpneumoniae_25X.fastq --nanopore_prefix kpneumoniae_25X
      Pacbio basecalled (.fastq) reads with nextflow general report
./nextflow run fmalmeida/MpGAP --threads 3 --outDir sample_dataset/outputs/pacbio_from_fastq \
--run_longreads_pipeline --lreads_type pacbio \
--longReads sample_dataset/pacbio/m140905_042212_sidney_c100564852550000001823085912221377_s1_X0.subreads.fastq -with-report
      Pacbio raw (subreads.bam) reads
./nextflow run fmalmeida/MpGAP --threads 3 --outDir sample_dataset/outputs/pacbio --run_longreads_pipeline \
--lreads_type pacbio --pacbio_bamPath sample_dataset/pacbio/m140905_042212_sidney_c100564852550000001823085912221377_s1_X0.subreads.bam
      Pacbio raw (legacy .bas.h5 to subreads.bam) reads
./nextflow run fmalmeida/MpGAP --threads 3 --outDir sample_dataset/outputs/pacbio --run_longreads_pipeline \
--lreads_type pacbio --pacbio_h5Path sample_dataset/pacbio/m140912_020930_00114_c100702482550000001823141103261590_s1_p0.1.bax.h5
   """.stripIndent()
}

/*
          Display Help Message
*/
params.help = false
 // Show help emssage
 if (params.help){
   helpMessage()
   file('work').deleteDir()
   file('.nextflow').deleteDir()
   exit 0
}

/*
          Display CLI examples
*/
params.show = false
 // Show help emssage
 if (params.show){
   exampleMessage()
   exit 0
}

/*
                    Setting Default Parameters.
                    Do not change any of this values
                    directly in main.nf.
                    Use the config file instead.

*/

params.longreads = ''
params.fast5Path = ''
params.pacbio_all_baxh5_path = ''
params.lr_type = ''
params.shortreads_paired = ''
params.shortreads_single = ''
params.ref_genome = ''
params.assembly_type = ''
params.illumina_polish_longreads_contigs = false
params.pilon_memmory_limit = 50
params.try_canu = false
params.try_unicycler = false
params.try_flye = false
params.try_spades = false
params.genomeSize = ''
params.outDir = 'output'
params.prefix = 'out'
params.threads = 3
params.cpus = 2
params.yaml = 'additional_parameters.yaml'

/*
                    Loading Parameters properly
                    set through config file.

*/

prefix = params.prefix
outdir = params.outDir
threads = params.threads
genomeSize = params.genomeSize
assembly_type = params.assembly_type
ref_genome = (params.ref_genome) ? file(params.ref_genome) : ''

/*
 * PARSING YAML FILE
 */

import org.yaml.snakeyaml.Yaml
//Def method for addtional parameters
class MyClass {
def getAdditional(String file, String value) {
  def yaml = new Yaml().load(new FileReader("$file"))
  def output = ""
  if ( "$value" == "canu" ) {
    yaml."$value".each {
  	   def (k, v) = "${it}".split( '=' )
  	    if ((v ==~ /null/ ) || (v == "")) {} else {
  	       output = output + " " + "${it}"
  	}}
    return output
  } else {
  yaml."$value".each {
    def (k, v) = "${it}".split( '=' )
    if ( v ==~ /true/ ) {
      output = output + " --" + k
      } else if ( v ==~ /false/ ) {}
        else if ((v ==~ /null/ ) || (v == "")) {} else {
          if ( k ==~ /k/ ) { output = output + " -" + k + " " + v }
          else { output = output + " --" + k + " " + v }
    }}
    return output
  }}}

if ( params.yaml ) {} else {
  exit 1, "YAML file not found: ${params.yaml}"
}

//Creating map for additional parameters
def additionalParameters = [:]
additionalParameters['Spades'] = new MyClass().getAdditional(params.yaml, 'spades')
additionalParameters['Unicycler'] = new MyClass().getAdditional(params.yaml, 'unicycler')
additionalParameters['Canu'] = new MyClass().getAdditional(params.yaml, 'canu')
additionalParameters['Pilon'] = new MyClass().getAdditional(params.yaml, 'pilon')
additionalParameters['Flye'] = new MyClass().getAdditional(params.yaml, 'flye')

/*
 * PIPELINE BEGIN
 * Assembly with longreads-only
 * Canu and Nanpolish or Unicycler
 */

// Loading long reads files
canu_lreads = (params.longreads && (params.try_canu) && params.assembly_type == 'longreads-only') ?
              file(params.longreads) : Channel.empty()
unicycler_lreads = (params.longreads && (params.try_unicycler) && params.assembly_type == 'longreads-only') ?
                   file(params.longreads) : Channel.empty()
flye_lreads = (params.longreads && (params.try_flye) && params.assembly_type == 'longreads-only') ?
                   file(params.longreads) : Channel.empty()
if (params.fast5Path && params.assembly_type == 'longreads-only') {
  fast5 = Channel.fromPath( params.fast5Path )
  nanopolish_lreads = file(params.longreads)
  fast5_dir = Channel.fromPath( params.fast5Path, type: 'dir' )
} else { Channel.empty().into{fast5; fast5_dir; nanopolish_lreads} }

// CANU ASSEMBLER - longreads
process canu_assembly {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  cpus threads

  input:
  file lreads from canu_lreads

  output:
  file "*"
  file("canu_lreadsOnly_results_${lrID}/*.contigs.fasta") into canu_contigs

  when:
  (params.try_canu) && assembly_type == 'longreads-only'

  script:
  lr = (params.lr_type == 'nanopore') ? '-nanopore-raw' : '-pacbio-raw'
  lrID = lreads.getSimpleName()
  """
  canu -p ${prefix} -d canu_lreadsOnly_results_${lrID} maxThreads=${params.threads}\
  genomeSize=${genomeSize} ${additionalParameters['Canu']} $lr $lreads
  """
}

// UNICYCLER ASSEMBLER - longreads-only
process unicycler_longReads {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  cpus threads

  input:
  file lreads from unicycler_lreads

  output:
  file "unicycler_lreadsOnly_results_${lrID}/"
  file("unicycler_lreadsOnly_results_${lrID}/assembly.fasta") into unicycler_longreads_contigs

  when:
  (params.try_unicycler) && assembly_type == 'longreads-only'

  script:
  lrID = lreads.getSimpleName()
  """
  unicycler -l $lreads \
  -o unicycler_lreadsOnly_results_${lrID} -t ${params.threads} \
  ${additionalParameters['Unicycler']} &> unicycler.log
  """
}

// Flye ASSEMBLER - longreads
process flye_assembly {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  cpus threads

  input:
  file lreads from flye_lreads

  output:
  file "flye_lreadsOnly_results_${lrID}/"
  file("flye_lreadsOnly_results_${lrID}/scaffolds.fasta") optional true
  file("flye_lreadsOnly_results_${lrID}/assembly_flye.fasta") into flye_contigs

  when:
  (params.try_flye) && assembly_type == 'longreads-only'

  script:
  lr = (params.lr_type == 'nanopore') ? '--nano-raw' : '--pacbio-raw'
  lrID = lreads.getSimpleName()
  """
  source activate flye ;
  flye ${lr} $lreads --genome-size ${genomeSize} --out-dir flye_lreadsOnly_results_${lrID} \
  --threads $threads ${additionalParameters['Flye']} &> flye.log ;
  mv flye_lreadsOnly_results_${lrID}/assembly.fasta flye_lreadsOnly_results_${lrID}/assembly_flye.fasta
  """
}


// Creating channels for assesing longreads assemblies
// For Nanopolish, quast and variantCaller
if (params.fast5Path) {
    longread_assembly_nanopolish = Channel.empty().mix(flye_contigs, canu_contigs, unicycler_longreads_contigs)
    longread_assemblies_variantCaller = Channel.empty()
} else if (params.lr_type == 'pacbio' && params.pacbio_all_baxh5_path != '') {
  longread_assembly_nanopolish = Channel.empty()
  longread_assemblies_variantCaller = Channel.empty().mix(flye_contigs, canu_contigs, unicycler_longreads_contigs)
} else {
  longread_assembly_nanopolish = Channel.empty()
  longread_assemblies_variantCaller = Channel.empty()
}

/*
 * NANOPOLISH - A tool to polish nanopore only assemblies
 */
process nanopolish {
  publishDir "${outdir}/lreadsOnly_nanopolished_contigs", mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  cpus threads

  input:
  each file(draft) from longread_assembly_nanopolish
  file(reads) from nanopolish_lreads
  file fast5
  val fast5_dir from fast5_dir

  output:
  file("${prefix}_${assembler}_nanopolished.fa") into nanopolished_contigs

  when:
  assembly_type == 'longreads-only' && (params.fast5Path)

  script:
  if (draft.getName()  == 'assembly.fasta' || draft.getName() =~ /unicycler/) {
    assembler = 'unicycler'
    } else if (draft.getName()  == 'assembly_flye.fasta' || draft.getName() =~ /flye/) {
      assembler = 'flye'
      } else {
        assembler = 'canu'
        }
  """
  zcat -f ${reads} > reads ;
  if [ \$(grep -c "^@" reads) -gt 0 ] ; then sed -n '1~4s/^@/>/p;2~4p' reads > reads.fa ; else mv reads reads.fa ; fi ;
  nanopolish index -d "${fast5_dir}" reads.fa ;
  minimap2 -d draft.mmi ${draft} ;
  minimap2 -ax map-ont -t ${params.threads} ${draft} reads.fa | samtools sort -o reads.sorted.bam -T reads.tmp ;
  samtools index reads.sorted.bam ;
  python /miniconda/bin/nanopolish_makerange.py ${draft} | parallel --results nanopolish.results -P ${params.cpus} \
  nanopolish variants --consensus -o polished.{1}.fa \
    -w {1} \
    -r reads.fa \
    -b reads.sorted.bam \
    -g ${draft} \
    --min-candidate-frequency 0.1;
  python /miniconda/bin/nanopolish_merge.py polished.*.fa > ${prefix}_${assembler}_nanopolished.fa
  """
}

/*
 * VariantCaller - A pacbio only polishing step
 */

// Loading files
baxh5 = (params.pacbio_all_baxh5_path) ? Channel.fromPath(params.pacbio_all_baxh5_path).buffer( size: 3 ) : Channel.empty()

process bax2bam {
  publishDir "${outdir}/subreads", mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  cpus threads

  input:
  file(bax) from baxh5

  output:
  file "*.subreads.bam" into pacbio_bams

  when:
  params.lr_type == 'pacbio' && params.pacbio_all_baxh5_path != ''

  script:
  """
  source activate pacbio ;
  bax2bam ${bax.join(" ")} --subread  \
  --pulsefeatures=DeletionQV,DeletionTag,InsertionQV,IPD,MergeQV,SubstitutionQV,PulseWidth,SubstitutionTag;
  """
}

// Get bams together
variantCaller_bams = Channel.empty().mix(pacbio_bams).collect()

process variantCaller {
  publishDir "${outdir}/lreadsOnly_pacbio_consensus", mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  cpus threads

  input:
  each file(draft) from longread_assemblies_variantCaller
  file bams from variantCaller_bams

  output:
  file "${prefix}_${assembler}_pbvariants.gff"
  file "${prefix}_${assembler}_pbconsensus.fasta" into variant_caller_contigs

  when:
  params.lr_type == 'pacbio' && params.pacbio_all_baxh5_path != ''

  script:
  assembler = (draft.getName()  == 'assembly.fasta' || draft.getName() =~ /unicycler/) ? 'unicycler' : 'canu'
  """
  source activate pacbio;
  for BAM in ${bams.join(" ")} ; do pbalign --nproc ${params.threads}  \
  \$BAM ${draft} \${BAM%%.bam}_pbaligned.bam; done;
  for BAM in *_pbaligned.bam ; do samtools sort -@ ${params.threads} \
  -o \${BAM%%.bam}_sorted.bam \$BAM; done;
  samtools merge pacbio_merged.bam *_sorted.bam;
  samtools index pacbio_merged.bam;
  pbindex pacbio_merged.bam;
  samtools faidx ${draft};
  arrow -j ${params.threads} --referenceFilename ${draft} -o ${prefix}_${assembler}_pbconsensus.fasta \
  -o ${prefix}_${assembler}_pbvariants.gff pacbio_merged.bam
  """

}

/*
 * HYBRID ASSEMBLY WITH Unicycler and Spades
 */
// Spades
// Loading paired end short reads
short_reads_spades_hybrid_paired = (params.shortreads_paired && params.assembly_type == 'hybrid' \
                                    && (params.try_spades)) ?
                                    Channel.fromFilePairs( params.shortreads_paired, flat: true, size: 2 ) : Channel.value(['', '', ''])
// Loading single end short reads
short_reads_spades_hybrid_single = (params.shortreads_single && params.assembly_type == 'hybrid' \
                                    && (params.try_spades)) ?
                                    Channel.fromPath(params.shortreads_single) : ''
// Long reads
spades_hybrid_lreads = (params.longreads && params.assembly_type == 'hybrid' && (params.try_spades)) ?
                        file(params.longreads) : ''

// Assembly begin
process spades_hybrid_assembly {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  tag { x }
  cpus threads

  input:
  file lreads from spades_hybrid_lreads
  set val(id), file(sread1), file(sread2) from short_reads_spades_hybrid_paired
  file(sread) from short_reads_spades_hybrid_single
  file ref_genome from ref_genome

  output:
  file("spades_hybrid_results_${rid}/contigs.fasta") into spades_hybrid_contigs
  file "*"

  when:
  assembly_type == 'hybrid' && (params.try_spades)

  script:
  lr = (params.lr_type == 'nanopore') ? '--nanopore' : '--pacbio'
  spades_opt = (params.ref_genome) ? "--trusted-contigs $ref_genome" : ''

  if ((params.shortreads_single) && (params.shortreads_paired)) {
    parameter = "-1 $sread1 -2 $sread2 -s $sread $lr $lreads"
    rid = sread.getSimpleName() + "_and_" + sread1.getSimpleName()
    x = "Executing assembly with paired and single end reads"
  } else if ((params.shortreads_single) && (params.shortreads_paired == '')) {
    parameter = "-s $sread $lr $lreads"
    rid = sread.getSimpleName()
    x = "Executing assembly with single end reads"
  } else if ((params.shortreads_paired) && (params.shortreads_single == '')) {
    parameter = "-1 $sread1 -2 $sread2 $lr $lreads"
    rid = sread1.getSimpleName()
    x = "Executing assembly with paired end reads"
  }
  """
  spades.py -o "spades_hybrid_results_${rid}" -t ${params.threads} ${additionalParameters['Spades']} \\
  $parameter ${spades_opt}
  """
}

// Unicycler
// Loading paired end short reads
short_reads_unicycler_hybrid_paired = (params.shortreads_paired && params.assembly_type == 'hybrid' \
                                       && (params.try_unicycler)) ?
                                       Channel.fromFilePairs( params.shortreads_paired, flat: true, size: 2 ) : Channel.value(['', '', ''])
// Loading single end short reads
short_reads_unicycler_hybrid_single = (params.shortreads_single && params.assembly_type == 'hybrid' \
                                       && (params.try_unicycler)) ?
                                       Channel.fromPath(params.shortreads_single) : ''
// Long reads
unicycler_hybrid_lreads = (params.longreads && params.assembly_type == 'hybrid' && (params.try_unicycler)) ?
                          file(params.longreads) : ''

// Assembly begin
process unicycler_hybrid_assembly {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  tag { x }
  cpus threads

  input:
  set val(id), file(sread1), file(sread2) from short_reads_unicycler_hybrid_paired
  file(sread) from short_reads_unicycler_hybrid_single
  file lreads from unicycler_hybrid_lreads

  output:
  file "*"
  file("unicycler_hybrid_results_${rid}/assembly.fasta") into unicycler_hybrid_contigs

  when:
  assembly_type == 'hybrid' && (params.try_unicycler)

  script:
  if ((params.shortreads_single) && (params.shortreads_paired)) {
    parameter = "-1 $sread1 -2 $sread2 -s $sread -l $lreads"
    rid = sread.getSimpleName() + "_and_" + sread1.getSimpleName()
    x = "Executing assembly with paired and single end reads"
  } else if ((params.shortreads_single) && (params.shortreads_paired == '')) {
    parameter = "-s $sread -l $lreads"
    rid = sread.getSimpleName()
    x = "Executing assembly with single end reads"
  } else if ((params.shortreads_paired) && (params.shortreads_single == '')) {
    parameter = "-1 $sread1 -2 $sread2 -l $lreads"
    rid = sread1.getSimpleName()
    x = "Executing assembly with paired end reads"
  }
  """
  unicycler $parameter \\
  -o unicycler_hybrid_results_${rid} -t ${params.threads} \\
  ${additionalParameters['Unicycler']} &>unicycler.log
  """
}

/*
 * ILLUMINA-ONLY ASSEMBLY WITH Unicycler and Spades
 */
// Spades
// Loading short reads
short_reads_spades_illumina_paired = (params.shortreads_paired && params.assembly_type == 'illumina-only' \
                                      && (params.try_spades)) ?
                                      Channel.fromFilePairs( params.shortreads_paired, flat: true, size: 2 ) : Channel.value(['', '', ''])
// Loading short reads
short_reads_spades_illumina_single = (params.shortreads_single && params.assembly_type == 'illumina-only' \
                                      && (params.try_spades)) ?
                                      Channel.fromPath(params.shortreads_single) : ''
// Assembly begin
process spades_illumina_assembly {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  tag { x }
  cpus threads

  input:
  set val(id), file(sread1), file(sread2) from short_reads_spades_illumina_paired
  file(sread) from short_reads_spades_illumina_single
  file ref_genome from ref_genome

  output:
  file("spades_illuminaOnly_results_${rid}/contigs.fasta") into spades_illumina_contigs
  file "*"

  when:
  assembly_type == 'illumina-only' && (params.try_spades)

  script:
  spades_opt = (params.ref_genome) ? "--trusted-contigs $ref_genome" : ''
  if ((params.shortreads_single) && (params.shortreads_paired)) {
    parameter = "-1 $sread1 -2 $sread2 -s $sread"
    rid = sread.getSimpleName() + "_and_" + sread1.getSimpleName()
    x = "Executing assembly with paired and single end reads"
  } else if ((params.shortreads_single) && (params.shortreads_paired == '')) {
    parameter = "-s $sread"
    rid = sread.getSimpleName()
    x = "Executing assembly with single end reads"
  } else if ((params.shortreads_paired) && (params.shortreads_single == '')) {
    parameter = "-1 $sread1 -2 $sread2"
    rid = sread1.getSimpleName()
    x = "Executing assembly with paired end reads"
  }
  """
  spades.py -o "spades_illuminaOnly_results_${rid}" -t ${params.threads} ${additionalParameters['Spades']} \\
  $parameter ${spades_opt}
  """
}

// Unicycler
// Loading short reads
short_reads_unicycler_illumina_single = (params.shortreads_single && params.assembly_type == 'illumina-only' \
                                         && (params.try_unicycler)) ?
                                         Channel.fromPath(params.shortreads_single) : ''
short_reads_unicycler_illumina_paired = (params.shortreads_paired && params.assembly_type == 'illumina-only' \
                                         && (params.try_unicycler)) ?
                                         Channel.fromFilePairs( params.shortreads_paired, flat: true, size: 2 ) : Channel.value(['', '', ''])
// Assembly begin
process unicycler_illumina_assembly {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  tag { x }
  cpus threads

  input:
  file(sread) from short_reads_unicycler_illumina_single
  set val(id), file(sread1), file(sread2) from short_reads_unicycler_illumina_paired

  output:
  file "*"
  file("unicycler_illuminaOnly_results_${rid}/assembly.fasta") into unicycler_illumina_contigs

  when:
  assembly_type == 'illumina-only' && (params.try_unicycler)

  script:
  if ((params.shortreads_single) && (params.shortreads_paired)) {
    parameter = "-1 $sread1 -2 $sread2 -s $sread"
    rid = sread.getSimpleName() + "_and_" + sread1.getSimpleName()
    x = "Executing assembly with paired and single end reads"
  } else if ((params.shortreads_single) && (params.shortreads_paired == '')) {
    parameter = "-s $sread"
    rid = sread.getSimpleName()
    x = "Executing assembly with single end reads"
  } else if ((params.shortreads_paired) && (params.shortreads_single == '')) {
    parameter = "-1 $sread1 -2 $sread2"
    rid = sread1.getSimpleName()
    x = "Executing assembly with paired end reads"
  }
  """
  unicycler $parameter \\
  -o unicycler_illuminaOnly_results_${rid} -t ${params.threads} \\
  ${additionalParameters['Unicycler']} &>unicycler.log
  """
}

/*
 * STEP 2 - ASSEMBLY POLISHING
 */

// Create a single value channel to make polishing step wait for assemblers to finish
/*
[unicycler_ok, unicycler_ok2] = ((params.try_unicycler) && params.pacbio_all_baxh5_path == '' && params.fast5Path == '') ? Channel.empty().mix(unicycler_execution) : Channel.value('OK')
[canu_ok, canu_ok2] = ((params.try_canu) && params.pacbio_all_baxh5_path == '' && params.fast5Path == '') ? Channel.empty().mix(canu_execution) : Channel.value('OK')
[flye_ok, flye_ok2] = ((params.try_flye) && params.pacbio_all_baxh5_path == '' && params.fast5Path == '') ? Channel.empty().mix(flye_execution) : Channel.value('OK')
[nanopolish_ok, nanopolish_ok2] = (params.fast5Path) ? Channel.empty().mix(nanopolish_execution) : Channel.value('OK')
[variantCaller_ok, variantCaller_ok2] = (params.pacbio_all_baxh5_path) ? Channel.empty().mix(variant_caller_execution) : Channel.value('OK')
*/

/*
 * Whenever the user have paired end shor reads, this pipeline will execute
 * the polishing step with Unicycler polish pipeline.
 *
 * Unicycler Polishing Pipeline
 */

//Load contigs
if (params.pacbio_all_baxh5_path != '' && (params.shortreads_paired) && params.illumina_polish_longreads_contigs == true) {
 Channel.empty().mix(variant_caller_contigs).set { unicycler_polish }
} else if (params.fast5Path && (params.shortreads_paired) && params.illumina_polish_longreads_contigs == true) {
 Channel.empty().mix(nanopolished_contigs).set { unicycler_polish }
} else if (params.pacbio_all_baxh5_path == '' && params.fast5Path == '' && (params.shortreads_paired) && params.illumina_polish_longreads_contigs == true) {
 Channel.empty().mix(flye_contigs, canu_contigs, unicycler_longreads_contigs).set { unicycler_polish }
} else { Channel.empty().set {unicycler_polish} }

//Loading reads for quast
short_reads_lreads_polish = (params.shortreads_paired) ? Channel.fromFilePairs( params.shortreads_paired, flat: true, size: 2 )
                                                       : Channel.value(['', '', ''])
process illumina_polish_longreads_contigs {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:Unicycler_Polish'
  cpus threads

  input:
  each file(draft) from unicycler_polish.collect()
  set val(id), file(sread1), file(sread2) from short_reads_lreads_polish

  output:
  file("${assembler}_lreadsOnly_exhaustive_polished")
  file("${assembler}_lreadsOnly_exhaustive_polished/${assembler}_final_polish.fasta") into unicycler_polished_contigs

  when:
  (assembly_type == 'longreads-only' && (params.illumina_polish_longreads_contigs) && (params.shortreads_paired))

  script:
  if (draft.getName()  == 'assembly.fasta' || draft.getName() =~ /unicycler/) {
    assembler = 'unicycler'
  } else if (draft.getName()  == 'assembly_flye.fasta' || draft.getName() =~ /flye/) {
    assembler = 'flye'
  } else { assembler = 'canu' }
  """
  mkdir ${assembler}_lreadsOnly_exhaustive_polished;
  unicycler_polish --ale /home/ALE/src/ALE --samtools /home/samtools-1.9/samtools --pilon /home/pilon/pilon-1.23.jar \
  -a $draft -1 $sread1 -2 $sread2 --threads $threads &> polish.log ;
  mv 0* polish.log ${assembler}_lreadsOnly_exhaustive_polished;
  mv ${assembler}_lreadsOnly_exhaustive_polished/*_final_polish.fasta ${assembler}_lreadsOnly_exhaustive_polished/${assembler}_final_polish.fasta;
  """
}

/*
 * Whenever the user have unpaired short reads, this pipeline will execute
 * the polishing step with a single Pilon round pipeline.
 *
 * Unicycler Polishing Pipeline
 */
//Load contigs
if (params.pacbio_all_baxh5_path != '' && (params.shortreads_single) && params.illumina_polish_longreads_contigs == true) {
Channel.empty().mix(variant_caller_contigs).set { pilon_polish }
} else if (params.fast5Path && (params.shortreads_single) && params.illumina_polish_longreads_contigs == true) {
Channel.empty().mix(nanopolished_contigs).set { pilon_polish }
} else if (params.pacbio_all_baxh5_path == '' && params.fast5Path == '' && (params.shortreads_single) && params.illumina_polish_longreads_contigs == true) {
Channel.empty().mix(flye_contigs, canu_contigs, unicycler_longreads_contigs).set { pilon_polish }
} else { Channel.empty().set { pilon_polish } }

//Load reads
short_reads_pilon_single = (params.shortreads_single) ?
                     Channel.fromPath(params.shortreads_single) : ''

process pilon_polish {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:ASSEMBLERS'
  cpus threads

  input:
  each file(draft) from pilon_polish.collect()
  file(sread) from short_reads_pilon_single

  output:
  file "pilon_results_${assembler}/pilon*"
  file("pilon_results_${assembler}/pilon*.fasta") into pilon_polished_contigs

  when:
  (assembly_type == 'longreads-only' && (params.illumina_polish_longreads_contigs) && (params.shortreads_single))

  script:
  parameter = "$sread"
  rid = sread.getSimpleName()
  x = "Polishing assembly with single end reads"

  if (draft.getName()  == 'assembly.fasta' || draft.getName() =~ /unicycler/) {
    assembler = 'unicycler'
  } else if (draft.getName()  == 'assembly_flye.fasta' || draft.getName() =~ /flye/) {
    assembler = 'flye'
  } else { assembler = 'canu' }
  """
  bwa index ${draft} ;
  bwa mem -M -t ${params.threads} ${draft} $parameter > ${rid}_${assembler}_aln.sam ;
  samtools view -bS ${rid}_${assembler}_aln.sam | samtools sort > ${rid}_${assembler}_aln.bam ;
  samtools index ${rid}_${assembler}_aln.bam ;
  java -Xmx${params.pilon_memmory_limit}G -jar /miniconda/share/pilon-1.22-1/pilon-1.22.jar \
  --genome ${draft} --bam ${rid}_${assembler}_aln.bam --output pilon_${assembler}_${rid} \
  --outdir pilon_results_${assembler} ${additionalParameters['Pilon']} &>pilon.log
  """
}

/*
 * STEP 3 -  Assembly quality assesment with QUAST
 */

//Load contigs
if (params.illumina_polish_longreads_contigs) {
  Channel.empty().mix(unicycler_polished_contigs, pilon_polished_contigs).set { final_assembly }
} else if (params.pacbio_all_baxh5_path != '' && params.illumina_polish_longreads_contigs == false ) {
  Channel.empty().mix(variant_caller_contigs).set { final_assembly }
} else if (params.fast5Path && params.illumina_polish_longreads_contigs == false ) {
  Channel.empty().mix(nanopolished_contigs).set { final_assembly }
} else { Channel.empty().mix(unicycler_polish, spades_hybrid_contigs, unicycler_hybrid_contigs, unicycler_illumina_contigs, spades_illumina_contigs).set { final_assembly } }
//Loading reads for quast
short_reads_quast_single = (params.shortreads_single) ? Channel.fromPath(params.shortreads_single) : ''
short_reads_quast_paired = (params.shortreads_paired) ? Channel.fromFilePairs( params.shortreads_paired, flat: true, size: 2 )
                                                      : Channel.value(['', '', ''])
long_reads_quast = (params.longreads) ? Channel.fromPath(params.longreads) : ''

process quast {
  publishDir outdir, mode: 'copy'
  container 'fmalmeida/compgen:QUAST'

  input:
  each file(contigs) from final_assembly
  file 'reference_genome' from ref_genome
  file('sread') from short_reads_quast_single
  file('lreads') from long_reads_quast
  set val(id), file('pread1'), file('pread2') from short_reads_quast_paired

  output:
  file "quast_${type}_outputs_${assembler}/*"

  script:
  if ((params.shortreads_single) && (params.shortreads_paired) && assembly_type != 'longreads-only') {
    ref_parameter = "-M -t ${params.threads} reference_genome sread pread1 pread2"
    parameter = "-M -t ${params.threads} ${contigs} pread1 pread2"
    x = "Assessing assembly with paired and single end reads"
    sreads_parameter = "--single sread"
    preads_parameter = "--pe1 pread1 --pe2 pread2"
    lreads_parameter = ""
  } else if ((params.shortreads_single) && (params.shortreads_paired == '') && assembly_type != 'longreads-only') {
    ref_parameter = "-M -t ${params.threads} reference_genome sread"
    parameter = "-M -t ${params.threads} ${contigs} sread"
    x = "Assessing assembly with single end reads"
    sreads_parameter = "--single sread"
    preads_parameter = ""
    lreads_parameter = ""
  } else if ((params.shortreads_paired) && (params.shortreads_single == '') && assembly_type != 'longreads-only') {
    ref_parameter = "-M -t ${params.threads} reference_genome pread1 pread2"
    parameter = "-M -t ${params.threads} ${contigs} pread1 pread2"
    x = "Assessing assembly with paired end reads"
    sreads_parameter = ""
    preads_parameter = "--pe1 pread1 --pe2 pread2"
    lreads_parameter = ""
  } else if (assembly_type == 'longreads-only') {
    ltype = (params.lr_type == 'nanopore') ? "ont2d" : "pacbio"
    parameter = "-x ${ltype} -t ${params.threads} ${contigs} lreads"
    ref_parameter = "-x ${ltype} -t ${params.threads} reference_genome lreads"
    x = "Assessing assembly with long reads"
    sreads_parameter = ""
    preads_parameter = ""
    lreads_parameter = "--${params.lr_type} lreads"
  }
  if (contigs.getName()  == 'assembly.fasta' || contigs.getName() =~ /unicycler/) {
    assembler = 'unicycler'
  } else if (contigs.getName()  == 'contigs.fasta' || contigs.getName() =~ /spades/) {
    assembler = 'spades'
  } else if (contigs.getName()  == 'assembly_flye.fasta' || contigs.getName() =~ /flye/) {
    assembler = 'flye'
  } else { assembler = 'canu' }

  if (assembly_type == 'longreads-only') {
    type = 'lreadsOnly'
  } else if (assembly_type == 'illumina-only') {
    type = 'illuminaOnly'
  } else if (assembly_type == 'hybrid') {
    type = 'hybrid'
  }
  if (params.ref_genome != '')
  """
  bwa index reference_genome ;
  bwa index ${contigs} ;
  bwa mem $parameter > contigs_aln.sam ;
  bwa mem $ref_parameter > reference_aln.sam ;
  quast.py -o quast_${type}_outputs_${assembler} -t ${params.threads} --ref-sam reference_aln.sam --sam contigs_aln.sam \\
  $sreads_parameter $preads_parameter $lreads_parameter -r reference_genome --circos ${contigs}
  """
  else
  """
  bwa index ${contigs} ;
  bwa mem $parameter > contigs_aln.sam ;
  quast.py -o quast_${type}_outputs_${assembler} -t ${params.threads} --sam contigs_aln.sam \\
  $sreads_parameter $preads_parameter $lreads_parameter --circos ${contigs}
  """
}


// Completition message
workflow.onComplete {
    println "Pipeline completed at: $workflow.complete"
    println "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
    println "Execution duration: $workflow.duration"
    // Remove work dir
    file('work').deleteDir()
}
/*
 * Header log info
 */
log.info "========================================="
log.info "     Docker-based assembly Pipeline      "
log.info "========================================="
def summary = [:]
summary['Long Reads']   = params.longreads
summary['Fast5 files dir']   = params.fast5Path
summary['Long Reads']   = params.longreads
summary['Short single end reads']   = params.shortreads_single
summary['Short paired end reads']   = params.shortreads_paired
summary['Fasta Ref']    = params.ref_genome
summary['Output dir']   = params.outDir
summary['Assembly assembly_type chosen'] = params.assembly_type
summary['Long read sequencing technology'] = params.lr_type
if(workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Current home']   = "$HOME"
summary['Current user']   = "$USER"
summary['Current path']   = "$PWD"
summary['Command used']   = "$workflow.commandLine"
log.info summary.collect { k,v -> "${k.padRight(15)}: $v" }.join("\n")
log.info "========================================="