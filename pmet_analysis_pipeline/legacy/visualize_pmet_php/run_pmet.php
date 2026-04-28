#!/usr/bin/php
<?php
//// TODO: Option for ATAC-seq data
// If choice = promoter, use fasta and gtf
// If choice = ATAC-seq, use peak file
// If choice = ATAC-seq, disable promoter length

// Fill in code to run ATAC-seq script
$scriptdir= dirname(__FILE__)."/";

//Read input parameters file
$input_file = $argv[1]; //"/cluster/tools/user_jobs/paulbrown/jukiz5/input_parameters_jukiz5"; //$argv[1];
$inputs = simplexml_load_file($input_file);

$mydir = $inputs->xpath('output_tmp_dir');
$mydir = $mydir[0];
if(substr($mydir, -1 ,1) != "/"){
	$mydir .= "/";
}

if (is_dir($mydir."progress"))
	system("rm -rf ".$mydir."progress");

$progressFile = $mydir."progress/progress";
if(!mkdir($mydir."progress"))
	die("Error creating output files!");

$fasta_file = "";
$meme_file = "";
$gene_input_file = "";

$max_motif_matches = $inputs->max_motif_matches;
$top_no_promoters = $inputs->top_no_promoters;

//Find out choice for target data
$target_data = $inputs->target_data; //interval or promoter

//For meme file, check whether defaults should be used
$upload_meme = $inputs->upload_meme;
if ($upload_meme == "JASPAR2018 Core Plants Non-Redundant") {
	$meme_file = $scriptdir."default_meme_files/JASPAR2018_CORE_plants_non-redundant.meme";
} else {
	$meme_file = $inputs->meme;
}

$gene_input_file = $inputs->gene_input;

writeProgress(0.01, "Processing inputs...", $progressFile);

$cmd = "";

//Run for promoters
if ($target_data == "Promoters") {

	$promoter_length = $inputs->promoter_length;
	$fasta_file = $inputs->fasta;
	$gtf_file = $inputs->gtf;
	$utr = $inputs->utr;
	$remove_overlap = $inputs->remove_overlap;

	//Include 5' UTR sequence?
	if ($utr = "Yes") {
		$utrscript = " -u Yes ";
	} else {
		$utrscript = " -u No ";
	}
	//Remove overlaps?
	if ($remove_overlap == "Yes") {
		$nooverlapscript = " -v NoOverlap ";
	} else {
		$nooverlapscript =  " -v AllowOverlap";
	}


	if ($fasta_file == "" || $gtf_file == "" || $meme_file == "" || $gene_input_file == "") {
		die( "Cannot run PMET. All files must be specified.\n");
	}

	// Construct the command for PMET Index
  // This makes promoter_lengths file, which  must have an entry for every gene in fimo files
	$cmd = $scriptdir."PMETindex_promoters.sh -r ".$scriptdir."scripts/ -o ".$mydir."indexoutput/ -g ".$progressFile." -i gene_id= -k ".$max_motif_matches." -n ".$top_no_promoters." -p ".$promoter_length." ".$utrscript.$nooverlapscript.$fasta_file." ".$gtf_file." ".$meme_file." ".$gene_input_file;

} else {
	//CODE TO RUN ATAC-SEQ = genomic intervals
	$fasta_file = $inputs->peaks; //captionned 'genomic intervals file'

	if ($fasta_file == "" || $meme_file == "" || $gene_input_file == "") {
		die( "Cannot run PMET. All files must be specified.\n");
	}

	echo "Running indexing...";
	// Construct the command for PMET Index
  // This makes promoter_lengths file, which  must have an entry for every gene in fimo files
	$cmd = $scriptdir."PMETindex_genome_intervals.sh -r ".$scriptdir."scripts/ -o ".$mydir."indexoutput/ -g ".$progressFile." -k ".$max_motif_matches." -n ".$top_no_promoters." ".$fasta_file." ".$meme_file." ".$gene_input_file;
}

echo "Running indexing...";
$errMsg = array();
exec(escapeshellcmd($cmd), $errMsg, $rv);
if (intval($rv)){
	// returned non-zero
	echo implode("\n", $errMsg);
	die("Error running PMET Index!\n");
}

writeProgress(0.95, "Running PMET Tool...", $progressFile);

//Construct the command for PMET tool
//uses the following default file names from indexing part
//binomial_thresholds.txt
//promotor_lengths.txt
//fimohits directory
//IC.txt
//In addition
//IC threshold=4 by default
//output - motif_found.txt

//-d in directoty where promoter_lengths, bin threshold, IC file, genes file and fimo 
//folder are found
//-o is directory where final spreadheet hits file is written

$cmd3 = $scriptdir."scripts/pmet -g ".$gene_input_file." -d ".$mydir."indexoutput/ -o ".$mydir." -s ".$progressFile;
$errMsg3 = array();

exec(escapeshellcmd($cmd3), $errMsg3, $rv3);

if (intval($rv3)){
  echo implode("\n",$errMsg3);
  die("Error running PMET Tool!");
}

// copy ui to local job folder
exec("cp ".$scriptdir."ui/heatmap.html ".$mydir);
exec("cp ".$scriptdir."ui/running.gif ".$mydir);
// exec("cp ".$scriptdir."ui/fimohits.html ".$mydir);
// exec("cp ".$scriptdir."ui/svgDownload.js ".$mydir);

// remove files
exec("rm -fr ".$mydir."fimohits");
exec("rm -f ".$mydir."binomial_thresholds.txt");
exec("rm -f ".$mydir."promoter_lengths.txt");
exec("rm -f ".$mydir."IC.txt");
exec("rm -fr ".$mydir."indexoutput");

// Got results
writeProgress(1.0, "Completed successfully\n", $progressFile);

function writeProgress($val, $msg, $progressFile){
	$fp = fopen($progressFile, "w"); //overwrite if present

	if (!$fp){
		die("Error creating output files");
	}
	fwrite($fp, $val."\t".$msg."\n");
	fclose($fp);
	echo $msg."\n";
}
?>
