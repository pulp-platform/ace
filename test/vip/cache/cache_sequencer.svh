`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_sequencer #(
    parameter int AW = 32,
    parameter int DW = 32
);

    mailbox #(cache_req)  cache_req_mbx;
    mailbox #(cache_resp) cache_resp_mbx;

    byte delimiter = " ";
    string txn_file;
    int unsigned txns_remaining;

    function new(
        mailbox #(cache_req)  cache_req_mbx,
        mailbox #(cache_resp) cache_resp_mbx,
        string txn_file
    );
        this.cache_req_mbx  = cache_req_mbx;
        this.cache_resp_mbx = cache_resp_mbx;
        this.txn_file       = txn_file;
    endfunction

    function automatic int parse_op(string op);
        if      (op == "REQ_LOAD")        return REQ_LOAD;
        else if (op == "REQ_STORE")       return REQ_STORE;
        else if (op == "CMO_FLUSH_NLINE") return CMO_FLUSH_NLINE;
        else $fatal(1, "Illegal operation type found");
    endfunction

    function automatic cache_req parse_txn(string line);
        cache_req req = new;
        logic [DW-1:0] word;
        string op;
        int size;
        op       = get_next_word(line);
        req.op   = parse_op(op);
        req.addr = get_next_word(line).atohex();
        word     = get_next_word(line).atohex();
        for (int i = 0; i < (DW / 8); i++) begin
            req.data_q.push_back(word[i +: 8]);
        end
        size               = get_next_word(line).atoi();
        req.uncacheable    = get_next_word(line).atoi();
        req.wr_policy_hint = get_next_word(line).atoi();
        return req;
    endfunction

    // Calculates the size of the next word until the delimiter
    function automatic int get_next_word_size(string line);
        byte char = "";
        int len, i;
        len = line.len();
        for (i = 0; i < len; i++) begin
            char = line[i];
            if (char == this.delimiter) break;
        end
        return i;
    endfunction

    // Returns the next word and removes it from ``line``
    function automatic string get_next_word(ref string line);
        int wsize;
        string word;
        int line_len = line.len();
        wsize = get_next_word_size(line);
        word = line.substr(0, wsize - 1);
        line = line.substr(wsize + 1, line_len - 1);
        return word;
    endfunction

    function automatic int get_n_transactions;
        int fd, ret;
        string line;
        int rows = 0;
        fd = $fopen(this.txn_file, "r");
        if (fd) begin
            while (!$feof(fd)) begin
                ret = $fgets(line, fd);
                rows++;
            end
        end else begin
            $fatal("Could not open file %s", txn_file);
        end
        $fclose(fd);
        return rows;
    endfunction

    task gen_txns_from_file;
        int fd, ret;
        string line;
        cache_req cache_req;
        fd = $fopen(this.txn_file, "r");
        if (fd) begin
            while (!$feof(fd)) begin
                int mbx_size;
                ret = $fgets(line, fd);
                cache_req = parse_txn(line);
                cache_req_mbx.put(cache_req);
            end
        end else begin
            $fatal("Could not open file %s", txn_file);
        end
        $fclose(fd);
    endtask

    task recv_resps;
        cache_resp cache_resp;
        cache_resp_mbx.get(cache_resp);
        txns_remaining--;
    endtask

    task run;
        txns_remaining = get_n_transactions();
        fork
            gen_txns_from_file();
            while (txns_remaining != 0) begin
                recv_resps();
            end
        join
    endtask

endclass