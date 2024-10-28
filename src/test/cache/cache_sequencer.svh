`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_sequencer #(
    parameter int AW = 32,
    parameter string txn_file = ""
);

    mailbox #(cache_req)  cache_req_mbx;

    byte delimiter = " ";

    function new(
        mailbox #(cache_req)  cache_req_mbx
    );
        this.cache_req_mbx  = cache_req_mbx;
    endfunction

    function automatic int parse_op(string op);
        if      (op == "REQ_LOAD")        return REQ_LOAD;
        else if (op == "REQ_STORE")       return REQ_STORE;
        else if (op == "CMO_FLUSH_NLINE") return CMO_FLUSH_NLINE;
        else $fatal("Illegal operation type found");
    endfunction

    function automatic cache_req parse_txn(string line);
        cache_req req;
        string op;
        op     = get_next_word(line);
        req.op = parse_op(op);
        req.addr           = get_next_word(line).atohex();
        req.data           = get_next_word(line).atohex();
        req.size           = get_next_word(line).atoi();
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
        wsize = get_next_word_size(line);
        word = line.substr(0, wsize - 1);
        line = line.substr(wsize + 1, line.len());
        return word;
    endfunction

    task gen_txns_from_file;
        int fd;
        string line;
        cache_req cache_req;
        fd = $fopen(txn_file, "r");
        if (fd) begin
            while (!$feof(fd)) begin
                $fgets(line, fd);
                cache_req = parse_txn(line);
                cache_req_mbx.put(cache_req);
            end
        end else begin
            $fatal("Could not open file %s", txn_file);
        end
        $fclose(fd);
    endtask

    task run;
        gen_txns_from_file();
    endtask

endclass