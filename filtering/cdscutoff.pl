use File::Spec qw (catfile);

my $genelist = shift;
my $genedir = shift;
my $cutoff = shift;

if ($cutoff > 0) {
	$cutoff = $cutoff / 100;
}
my @genes = ();
open FH, "<", $genelist;
foreach my $line (<FH>) {
	chomp $line;
	push @genes, $line;
}
close FH;

my $perc = "0";
$cutoffstr = sprintf("%.2f", $cutoff);
print "$cutoffstr\n";
if ($cutoffstr =~ /\d+\.(\d{2})/) {
	$perc = $1;
}
open OUTFH, ">", "cutoff.$perc";
foreach my $gene (@genes) {
	open FH, "<", File::Spec->catfile($genedir, $gene);
	my $totalident = 0;
	my $totallength = 0;
	foreach my $line (<FH>) {
		#Potri.001G001400.1.CDS.1	1621	1733	106	113
		my ($name, $start, $end, $ident, $length) = split (/\t/, $line);
		if ($name =~ /\.CDS\.1/) {
			$totalident += $ident;
			$totallength += $length;
		}
	}
	close FH;
	if (($totallength > 0) && (($totalident/$totallength) > $cutoff)){
		print OUTFH "$gene\n";
		print "$gene\t".($totalident/$totallength)."\n";
	}
}
close OUTFH;