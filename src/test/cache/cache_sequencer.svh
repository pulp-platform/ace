`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_scoreboard #(
    parameter int AW = 32,
    parameter string txn_file = ""
);
    struct {
        aw_beat_t aw_beat,
        ar_beat_t ar_beat,
        w_beat_t w_beat
    } st_beat;

    mailbox #(cache_req)  cache_req_mbx;
    mailbox #(cache_resp) cache_resp_mbx;

    automatic function st_beat parse_txn(string line);
        ace_test_pkg::ace_ax_comb_beat_t beat;
        string txn_type;
        $sscanf(line, "%s,", txn_type, beat.snoop, beat.addr, beat.id, beat.len, 
                             beat.size, beat.burst, beat.lock, beat.cache,
                             beat.prot, beat.qos, beat.region, beat.user,
                             beat.bar, beat.domain, beat.atop, beat.awunique);
    endfunction

    task gen_txns_from_file;
        int fd;
        string line;
        fd = $fopen(txn_file);
        if (fd) begin
            while (!$feof(fd)) begin
                $fgets(line, fd);
                parse_txn(line);
            end
        end else begin
            $fatal("Could not open file %s", txn_file)
        end
        $fclose(fd);
    endtask

endclass