/*
-----------------------------------------------------------------------------------
Neoantigen depletion  by clonality
PostgreSQL implementation of Rooney et all (Cell 2015) neoantigen depletion method
See https://www.ncbi.nlm.nih.gov/pubmed/25594174
Authors: Fred Varn, Floris barthel
-----------------------------------------------------------------------------------

Makes analysis.neoantigen_depletion_clonality materialized view
- Results from this query are directly used to make Figure 4D

## TERMS ##

Nbar: the expected number of non-silent mutations per silent mutation
Bbar: the expected number of high-affinity neo-peptide binders per non-silent mutation

** Here we compute Nbar and Bbar by summing all samples in the gold set **

Npred: the predicted number of non-silent mutations in sample s and clonality c
Bpred: the predicted number of neo-peptide binders in sample s and clonality c
Nobs: the observed number of non-silent mutations in sample s and clonality c
Bobs: the observed number of neoepitope-generating SNVs in sample s and clonality c

** Npred and Bpred are calculated using the observed silent mutations in sample s, Bbar and Nbar **

Rneo: the ratio between the observed and expected rate of neo-peptides

- Since the observed values and Nbar/Bbar were defined based on the same dataset, this ratio follows a normal distribution and is centered at one
- Lower values of this score can be interpreted as evidence of higher neoantigen depletion relative to other samples in the dataset

*/

WITH selected_tumor_pairs AS 
(
	SELECT gold_set.tumor_pair_barcode,
		gold_set.case_barcode,
		gold_set.tumor_barcode_a,
		gold_set.tumor_barcode_b
	FROM analysis.gold_set
), 
selected_aliquots AS 
(
	SELECT selected_tumor_pairs.tumor_barcode_a AS aliquot_barcode,
		selected_tumor_pairs.case_barcode,
		'P'::text AS sample_type
	FROM selected_tumor_pairs
	UNION
	SELECT selected_tumor_pairs.tumor_barcode_b AS aliquot_barcode,
		selected_tumor_pairs.case_barcode,
		'R'::text AS sample_type
	FROM selected_tumor_pairs
),
filtered_neoag AS 
(
	SELECT nag.aliquot_barcode,
		nag.variant_id,
		count(*) AS count
	FROM analysis.neoantigens_by_aliquot nag
	GROUP BY nag.aliquot_barcode, nag.variant_id
), 
variant_context_counts AS 
(
	SELECT pg.aliquot_barcode,
	CASE
		WHEN pg.pyclone_ccf >= 0.5 THEN 'C'::text
		WHEN pg.pyclone_ccf < 0.5 AND pg.pyclone_ccf >=0.1  THEN 'S'::text
		ELSE NULL::text
		END AS clonality,
	CASE
		WHEN pv.variant_classification::text = 'Missense_Mutation'::text THEN 'non'::text --ANY (ARRAY['Missense_Mutation'::character varying::text, 'START_CODON_SNP'::character varying::text, 'NONSTOP'::character varying::text]) THEN 'non'::text
		WHEN pv.variant_classification::text = 'Silent'::text THEN 'syn'::text
		ELSE NULL::text
		END AS variant_class,
	CASE
		WHEN nag.count > 0 THEN 'imm'::text
		WHEN nag.count IS NULL OR nag.count <= 0 THEN 'non'::text
		ELSE NULL::text
		END AS immune_fraction,
	pa.trinucleotide_context,
	pv.alt,
	count(*) AS mut_n
	FROM variants.passgeno pg
	JOIN selected_aliquots sa ON sa.aliquot_barcode = pg.aliquot_barcode
	JOIN variants.passvep pv ON pv.variant_id = pg.variant_id	
	JOIN variants.passanno pa ON pa.variant_id = pg.variant_id
	LEFT JOIN filtered_neoag nag ON nag.aliquot_barcode = pg.aliquot_barcode AND nag.variant_id = pg.variant_id
	WHERE pg.ssm2_pass_call IS TRUE AND pg.pyclone_ccf >= 0.1 AND pv.variant_type = 'SNP'::bpchar AND (pg.ad_alt + pg.ad_ref) >= 15 AND (pv.variant_classification::text = ANY(ARRAY['Missense_Mutation'::character varying::text,'Silent'::character varying::text])) --ANY (ARRAY['Missense_Mutation'::character varying::text, 'Silent'::character varying::text, 'START_CODON_SNP'::character varying::text, 'NONSTOP'::character varying::text]))
	GROUP BY pg.aliquot_barcode, (
		CASE
			WHEN pg.pyclone_ccf >= 0.5 THEN 'C'::text
			WHEN pg.pyclone_ccf < 0.5 AND pg.pyclone_ccf >=0.1  THEN 'S'::text
			ELSE NULL::text
		END), (
		CASE
			WHEN pv.variant_classification::text = 'Missense_Mutation'::text THEN 'non'::text --ANY (ARRAY['Missense_Mutation'::character varying::text, 'START_CODON_SNP'::character varying::text, 'NONSTOP'::character varying::text]) THEN 'non'::text
			WHEN pv.variant_classification::text = 'Silent'::text THEN 'syn'::text
			ELSE NULL::text
		END), (
		CASE
			WHEN nag.count > 0 THEN 'imm'::text
			WHEN nag.count IS NULL OR nag.count <= 0 THEN 'non'::text
			ELSE NULL::text
		END), 
		pa.trinucleotide_context, pv.alt
),
mis AS 
(
	SELECT variant_context_counts.trinucleotide_context,
		variant_context_counts.alt,
		sum(variant_context_counts.mut_n) AS n
	FROM variant_context_counts
	WHERE variant_context_counts.variant_class = 'non'::text
	GROUP BY variant_context_counts.trinucleotide_context, variant_context_counts.alt
),
syn AS 
(
	SELECT variant_context_counts.trinucleotide_context,
		variant_context_counts.alt,
		sum(variant_context_counts.mut_n) AS n
	FROM variant_context_counts
	WHERE variant_context_counts.variant_class = 'syn'::text
	GROUP BY variant_context_counts.trinucleotide_context, variant_context_counts.alt
), 
imm AS 
(
	SELECT variant_context_counts.trinucleotide_context,
		variant_context_counts.alt,
		sum(variant_context_counts.mut_n) AS n
	FROM variant_context_counts
	WHERE variant_context_counts.variant_class = 'non'::text AND variant_context_counts.immune_fraction = 'imm'::text
	GROUP BY variant_context_counts.trinucleotide_context, variant_context_counts.alt
), 
nbar AS 
(
	SELECT mis.trinucleotide_context,
	mis.alt,
	COALESCE(mis.n, 0::numeric) / NULLIF(syn.n, 0::numeric) AS nbar
	FROM mis
	FULL JOIN syn ON syn.trinucleotide_context = mis.trinucleotide_context AND syn.alt::text = mis.alt::text
), 
bbar AS 
(
	SELECT imm.trinucleotide_context,
		imm.alt,
		COALESCE(imm.n, 0::numeric) / NULLIF(mis.n, 0::numeric) AS bbar
	FROM imm
	FULL JOIN mis ON mis.trinucleotide_context = imm.trinucleotide_context AND mis.alt::text = imm.alt::text
), 
sil AS 
(
	SELECT variant_context_counts.aliquot_barcode,
		variant_context_counts.clonality,
		variant_context_counts.trinucleotide_context,
		variant_context_counts.alt,
		sum(variant_context_counts.mut_n) AS n
	FROM variant_context_counts
	WHERE variant_context_counts.variant_class = 'syn'::text
	GROUP BY variant_context_counts.aliquot_barcode, variant_context_counts.clonality, variant_context_counts.trinucleotide_context, variant_context_counts.alt
), 
npred AS 
(
	SELECT sil.aliquot_barcode,
		sil.clonality,
		sum(nbar.nbar * sil.n) AS npred
	FROM sil
	FULL JOIN nbar ON nbar.trinucleotide_context = sil.trinucleotide_context AND nbar.alt::text = sil.alt::text
	GROUP BY sil.aliquot_barcode, sil.clonality
), 
bpred AS 
(
	SELECT sil.aliquot_barcode,
		sil.clonality,
		sum(nbar.nbar * sil.n * bbar.bbar) AS bpred
	FROM sil
	FULL JOIN nbar ON nbar.trinucleotide_context = sil.trinucleotide_context AND nbar.alt::text = sil.alt::text
	FULL JOIN bbar ON bbar.trinucleotide_context = sil.trinucleotide_context AND bbar.alt::text = sil.alt::text
	GROUP BY sil.aliquot_barcode, sil.clonality
), 
obs AS 
(
	SELECT variant_context_counts.aliquot_barcode,
		variant_context_counts.clonality,
	sum(
		CASE
		WHEN variant_context_counts.variant_class = 'non'::text AND variant_context_counts.immune_fraction = 'imm'::text THEN variant_context_counts.mut_n
		ELSE 0::bigint
		END) AS bobs,
	sum(
		CASE
		WHEN variant_context_counts.variant_class = 'non'::text THEN variant_context_counts.mut_n
		ELSE 0::bigint
		END) AS nobs
	FROM variant_context_counts
	GROUP BY variant_context_counts.aliquot_barcode, variant_context_counts.clonality
)
SELECT obs.aliquot_barcode,
	obs.clonality,
	obs.bobs,
	obs.nobs,
	bpred.bpred,
	npred.npred,
	obs.bobs / NULLIF(obs.nobs, 0::numeric) AS obs,
	COALESCE(bpred.bpred, 0::numeric) / NULLIF(npred.npred, 0::numeric) AS exp,
	COALESCE(obs.bobs, 0::numeric) / NULLIF(obs.nobs, 0::numeric) / NULLIF(COALESCE(bpred.bpred, 0::numeric) / NULLIF(npred.npred, 0::numeric), 0::numeric) AS rneo
FROM obs
JOIN bpred ON bpred.aliquot_barcode = obs.aliquot_barcode AND bpred.clonality = obs.clonality
JOIN npred ON npred.aliquot_barcode = obs.aliquot_barcode AND npred.clonality = obs.clonality
--WHERE nobs >= 3
ORDER BY (COALESCE(obs.bobs, 0::numeric) / NULLIF(obs.nobs, 0::numeric) / NULLIF(COALESCE(bpred.bpred, 0::numeric) / NULLIF(npred.npred, 0::numeric), 0::numeric)) DESC;
