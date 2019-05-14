WITH normal_contamination_a AS
(
	SELECT ss.tumor_pair_barcode, ss.tumor_barcode_a, pur.normal_contamination AS normal_contamination_a
	FROM analysis.silver_set ss
	LEFT JOIN analysis.pairs pairs ON ss.tumor_barcode_a = pairs.tumor_barcode
	LEFT JOIN variants.titan_params pur ON pur.pair_barcode = pairs.pair_barcode
),
normal_contamination_b AS
(
	SELECT ss.tumor_pair_barcode, ss.tumor_barcode_b, pur.normal_contamination AS normal_contamination_b
	FROM analysis.silver_set ss
	LEFT JOIN analysis.pairs pairs ON ss.tumor_barcode_b = pairs.tumor_barcode
	LEFT JOIN variants.titan_params pur ON pur.pair_barcode = pairs.pair_barcode
),
nc_pair AS
(
	SELECT na.tumor_pair_barcode, tumor_barcode_a, tumor_barcode_b, normal_contamination_a, normal_contamination_b
	FROM normal_contamination_a na
	JOIN normal_contamination_b nb ON na.tumor_pair_barcode = nb.tumor_pair_barcode
),
t1 AS
(
	SELECT gt.tumor_pair_barcode,gt.chrom,gt.pos,gt.alt,gt.gene_symbol,neo.fraction,gt.tumor_barcode_a,gt.tumor_barcode_b,gt.surgical_interval_mo,netmhcpan_mt_score,received_tmz,received_rt,hypermutator_status,surg.treatment_chemotherapy_other,idh_codel_subtype, normal_contamination_a, normal_contamination_b, row_number() OVER w AS neoag_number,
	(CASE WHEN netmhcpan_mt_score IS NULL THEN 0 WHEN netmhcpan_mt_score IS NOT NULL THEN 1 END) AS neoantigen,
	(CASE WHEN netmhcpan_mt_score IS NULL OR netmhcpan_mt_score IS NOT NULL AND netmhcpan_mt_score > 50 THEN 0 WHEN netmhcpan_mt_score IS NOT NULL AND netmhcpan_mt_score <= 50 THEN 1 END) AS strong_neoantigen
	FROM variants.pgeno gt
	INNER JOIN analysis.silver_set ss ON ss.tumor_pair_barcode = gt.tumor_pair_barcode
	INNER JOIN analysis.neoantigens_by_pair neo ON 
		gt.tumor_pair_barcode = neo.tumor_pair_barcode AND 
		gt.chrom = CAST(neo.chrom AS INT) AND 
		gt.pos = neo.pos AND
		gt.alt = neo.alt
	LEFT JOIN analysis.tumor_clinical_comparison clin ON
		gt.tumor_pair_barcode = clin.tumor_pair_barcode
	LEFT JOIN clinical.surgeries surg ON
		substr(gt.tumor_barcode_a,1,15) = surg.sample_barcode
	LEFT JOIN nc_pair nc ON
		gt.tumor_pair_barcode = nc.tumor_pair_barcode
	WHERE (mutect2_call_a OR mutect2_call_b) AND ((ref_count_a + alt_count_a) >= 15 OR (ref_count_b + alt_count_b) >= 15)
	WINDOW w AS (PARTITION BY gt.tumor_pair_barcode,gt.chrom,gt.pos,gt.alt ORDER BY netmhcpan_mt_score)
)
SELECT * FROM t1 WHERE neoag_number = 1 ORDER BY tumor_pair_barcode