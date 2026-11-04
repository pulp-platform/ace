BENDER         ?= bender
VERIBLE_FORMAT ?= verible-verilog-format
VERIBLE_LINT   ?= verible-verilog-lint
PROJ_ROOT      = $(abspath ..)

format:
	$(VERIBLE_FORMAT) \
		--inplace \
		--indentation_spaces=4 \
		--column_limit=100 \
		--assignment_statement_alignment=align \
		--case_items_alignment=align \
		--module_net_variable_alignment=align \
		--port_declarations_alignment=align \
		--named_parameter_alignment=align \
		--named_port_alignment=align \
		--formal_parameters_alignment=align \
		--struct_union_members_alignment=align \
		--compact_indexing_and_selections=true \
		--port_declarations_right_align_packed_dimensions=true \
		--port_declarations_right_align_unpacked_dimensions=true \
		$$($(BENDER) script --no-deps -d $(PROJ_ROOT) flist)

lint:
	$(VERIBLE_LINT) \
    --rules_config verible_rules.cfg \
    --waiver_files verible.waiver \
    $$($(BENDER) script --no-deps -d $(PROJ_ROOT) flist)
