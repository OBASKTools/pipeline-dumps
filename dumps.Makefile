SHELL=/bin/bash -o pipefail # This ensures that when you run a pipe, any command can fail the pipeline (default, only the last)
ROBOT=robot

# Specifies the name of the log file used to record the time each target starts and ends.
LOG_FILE=pipeline_dumps.log

# Function to log start and end times, as well as errors
define log
    @echo $1 started: `date +%s` >> $(LOG_FILE)
    $2 || { echo "$1 failed: `date +%s`" >> $(LOG_FILE); exit 1; }
    @echo $1 ended: `date +%s` >> $(LOG_FILE)
endef

.PHONY: checkenv

# Executing this ensures that the necessary environment variables are set.
checkenv:
ifndef OUTDIR
	$(error OUTDIR environment variable not set)
endif
ifndef RAW_DUMPS_DIR
	$(error RAW_DUMPS_DIR environment variable not set)
endif
ifndef FINAL_DUMPS_DIR
	$(error FINAL_DUMPS_DIR environment variable not set)
endif
ifndef WORKSPACE
	$(error WORKSPACE environment variable not set)
endif
ifndef SPARQL_DIR
	$(error SPARQL_DIR environment variable not set)
endif
ifndef NEO4J2OWL_CONFIG
	$(error NEO4J2OWL_CONFIG environment variable not set)
endif
ifndef SCRIPTS_DIR
	$(error SCRIPTS_DIR environment variable not set)
endif
ifndef STDOUT_FILTER
$(error STDOUT_FILTER environment variable not set)
endif
ifndef INFER_ANNOTATE_RELATION
$(error INFER_ANNOTATE_RELATION environment variable not set)
endif
ifndef UNIQUE_FACETS_ANNOTATION
$(error UNIQUE_FACETS_ANNOTATION environment variable not set)
endif

all: checkenv $(FINAL_DUMPS_DIR)/owlery.owl $(FINAL_DUMPS_DIR)/solr.json $(FINAL_DUMPS_DIR)/pdb.owl pdb_csvs

$(RAW_DUMPS_DIR)/%.ttl:
	$(call log, $@, curl -G --data-urlencode "query=`cat $(SPARQL_DIR)/construct_$*.sparql`" $(SPARQL_ENDPOINT) -o $@)

$(RAW_DUMPS_DIR)/construct_%.owl: $(RAW_DUMPS_DIR)/%.ttl
	$(call log, $@, $(ROBOT) merge -i $< \
		annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/$*.owl" \
		convert -f owl -o $@ $(STDOUT_FILTER))

$(RAW_DUMPS_DIR)/construct_all.owl: $(RAW_DUMPS_DIR)/all.ttl
	$(call log, $@, $(ROBOT) merge -i $< \
		reason --reasoner ELK --axiom-generators "SubClass EquivalentClass ClassAssertion" --exclude-tautologies structural \
		relax \
		reduce --reasoner ELK --named-classes-only true \
		annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/all.owl" \
		convert -f owl -o $@ $(STDOUT_FILTER))

$(RAW_DUMPS_DIR)/inferred_annotation.owl: $(FINAL_DUMPS_DIR)/owlery.owl $(NEO4J2OWL_CONFIG)
	$(call log, $@, java -jar $ $(SCRIPTS_DIR)/infer-annotate.jar $^ $(INFER_ANNOTATE_RELATION) $@)

$(RAW_DUMPS_DIR)/unique_facets.owl: $(FINAL_DUMPS_DIR)/owlery.owl $(NEO4J2OWL_CONFIG)
	$(call log, $@, java -jar $ $(SCRIPTS_DIR)/infer-annotate.jar $^ $(UNIQUE_FACETS_ANNOTATION) $@ true)

$(FINAL_DUMPS_DIR)/solr.json: $(FINAL_DUMPS_DIR)/obographs.json $(NEO4J2OWL_CONFIG)
	python3 $(SCRIPTS_DIR)/obographs-solr.py $^ $@

# Add a new dump update the pipeline config:
# 1. pick name, add to the correct DUMPS variable (DUMPS_SOLR, DUMPS_PDB, DUMPS_OWLERY)
# 2. create new sparql query in sparql/, naming it 'construct_name.sparql', e.g. sparql/construct_image_names.sparql
# Note that non-sparql goals, like 'inferred_annotation', need to be added separately
# DUMPS_SOLR=$(DUMPS_SOLR)
# DUMPS_PDB=$(DUMPS_PDB)
# DUMPS_OWLERY=$(DUMPS_OWLERY)
CSV_IMPORTS="$(FINAL_DUMPS_DIR)/csv_imports"
OWL2NEOCSV="$(SCRIPTS_DIR)/owl2neo4jcsv.jar"
# jar requires a url with a file protocol
NEO4J2OWL_CONFIG_FILE="file://$(readlink --canonicalize $CSV_IMPORTS)/neo4j2owl-config.yaml"

$(CSV_IMPORTS):
	mkdir -p $@
	cp $(NEO4J2OWL_CONFIG) $(CSV_IMPORTS)

$(FINAL_DUMPS_DIR)/obographs.json: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_SOLR)) $(RAW_DUMPS_DIR)/inferred_annotation.owl $(RAW_DUMPS_DIR)/unique_facets.owl
	$(call log, $@, $(ROBOT) merge $(patsubst %, -i %, $^) convert -f json -o $@ $(STDOUT_FILTER))

$(FINAL_DUMPS_DIR)/pdb.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_PDB)) $(RAW_DUMPS_DIR)/inferred_annotation.owl $(RAW_DUMPS_DIR)/unique_facets.owl
	$(call log, $@, $(ROBOT) merge $(patsubst %, -i %, $^) -o $@ $(STDOUT_FILTER))

$(FINAL_DUMPS_DIR)/owlery.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_OWLERY))
	$(call log, $@, $(ROBOT) filter -i $< --axioms "logical" --preserve-structure true annotate \
	--ontology-iri "http://virtualflybrain.org/data/VFB/OWL/owlery.owl" -o $@ $(STDOUT_FILTER))

pdb_csvs: $(FINAL_DUMPS_DIR)/pdb.owl | $(CSV_IMPORTS)
	$(call log, $@, java $(ROBOT_ARGS) -jar $(OWL2NEOCSV) $< "$(NEO4J2OWL_CONFIG_FILE)" $(CSV_IMPORTS))
	@echo "=== Cleaning up CSVs: sort relationships ==="
	@cd $(CSV_IMPORTS) && bash $(SCRIPTS_DIR)/csv_sorter.sh
	@echo "=== Print Timer Logs ==="
	@cat $(LOG_FILE)

