// Copyright (c) 2025 ETH Zurich, University of Bologna
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

module ace_ar_transaction_decoder import ace_pkg::*; #(
    parameter bit  LEGACY    = 0,
    parameter type ar_chan_t = logic
)(
    // Input channel
    input  ar_chan_t ar_i,
    // Control signals
    output logic        snooping_o,
    output snoop_info_t snoop_info_o,
    output logic        illegal_trs_o
);

arsnoop_t arsnoop;
logic     lock;

logic     is_shareable;
logic     is_system;
logic     is_barrier;

logic read_no_snoop;
logic read_once;
logic read_shared;
logic read_clean;
logic read_not_shared_dirty;
logic read_unique;
logic clean_unique;
logic make_unique;
logic clean_shared;
logic clean_invalid;
logic make_invalid;
logic barrier;
logic dvm_complete;
logic dvm_message;

assign arsnoop      = ar_i.snoop;
assign lock         = ar_i.lock;

assign is_shareable = ar_i.domain inside {InnerShareable, OuterShareable};
assign is_system    = ar_i.domain inside {System};
assign is_barrier   = ar_i.bar inside {MemoryBarrier, SynchronizationBarrier};

assign read_no_snoop         = !is_barrier && !is_shareable && arsnoop == arsnoop_t'(ReadNoSnoop);
assign read_once             = !is_barrier &&  is_shareable && arsnoop == arsnoop_t'(ReadOnce);
assign read_shared           = !is_barrier &&  is_shareable && arsnoop == arsnoop_t'(ReadShared);
assign read_clean            = !is_barrier &&  is_shareable && arsnoop == arsnoop_t'(ReadClean);
assign read_not_shared_dirty = !is_barrier &&  is_shareable && arsnoop == arsnoop_t'(ReadNotSharedDirty);
assign read_unique           = !is_barrier &&  is_shareable && arsnoop == arsnoop_t'(ReadUnique);
assign clean_unique          = !is_barrier &&  is_shareable && arsnoop == arsnoop_t'(CleanUnique);
assign make_unique           = !is_barrier &&  is_shareable && arsnoop == arsnoop_t'(MakeUnique);
assign clean_shared          = !is_barrier && !is_system    && arsnoop == arsnoop_t'(CleanShared);
assign clean_invalid         = !is_barrier && !is_system    && arsnoop == arsnoop_t'(CleanInvalid);
assign make_invalid          = !is_barrier && !is_system    && arsnoop == arsnoop_t'(MakeInvalid);
assign barrier               =  is_barrier                  && arsnoop == arsnoop_t'(Barrier);
assign dvm_complete          = !is_barrier &&  is_shareable && arsnoop == arsnoop_t'(DVMComplete);
assign dvm_message           = !is_barrier &&  is_shareable && arsnoop == arsnoop_t'(DVMMessage);

always_comb begin
    illegal_trs_o  = 1'b0;
    snooping_o     = 1'b1;
    snoop_info_o.snoop_trs = acsnoop_t'(arsnoop);
    snoop_info_o.accepts_dirty        = 1'b0;
    snoop_info_o.accepts_dirty_shared = 1'b0;
    snoop_info_o.accepts_shared       = 1'b0;
    unique case (1'b1)
        read_no_snoop: begin
            snooping_o = 1'b0;
        end
        read_once: begin
            snoop_info_o.accepts_shared       = 1'b1;
            if (LEGACY && lock)
                snoop_info_o.snoop_trs = acsnoop_t'(CleanInvalid);
        end
        read_shared: begin
            snoop_info_o.accepts_dirty        = 1'b1;
            snoop_info_o.accepts_dirty_shared = 1'b1;
            snoop_info_o.accepts_shared       = 1'b1;
        end
        read_clean: begin
            snoop_info_o.accepts_shared       = 1'b1;
        end
        read_not_shared_dirty: begin
            snoop_info_o.accepts_dirty        = 1'b1;
            snoop_info_o.accepts_shared       = 1'b1;
        end
        read_unique: begin
            snoop_info_o.accepts_dirty        = 1'b1;
        end
        clean_unique: begin
            snoop_info_o.snoop_trs = acsnoop_t'(CleanInvalid);
        end
        make_unique: begin
             snoop_info_o.snoop_trs = acsnoop_t'(MakeInvalid);
        end
        clean_shared: begin
            snoop_info_o.accepts_shared       = 1'b1;
        end
        clean_invalid: begin
        end
        make_invalid: begin
        end
        barrier: begin
        end
        dvm_complete: begin
        end
        dvm_message: begin
        end
        default: illegal_trs_o = 1'b1;
    endcase
end


endmodule
