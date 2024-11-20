`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_sequencer #(
    parameter int AW        = 32,
    parameter int DW        = 32,
    parameter type clk_if_t = logic
);

    mailbox #(cache_req)  cache_req_mbx;
    mailbox #(cache_resp) cache_resp_mbx;

    byte delimiter = " ";
    string txn_file;
    int unsigned txns_remaining;
    int unsigned clk_cnt = 0;

    // Interface to provide simulation clock
    clk_if_t clk_if;

    function new(
        clk_if_t              clk_if,
        mailbox #(cache_req)  cache_req_mbx,
        mailbox #(cache_resp) cache_resp_mbx,
        string txn_file
    );
        this.clk_if         = clk_if;
        this.cache_req_mbx  = cache_req_mbx;
        this.cache_resp_mbx = cache_resp_mbx;
        this.txn_file       = txn_file;
    endfunction

    function automatic int parse_op(string op);
        if      (op == "REQ_LOAD")        return REQ_LOAD;
        else if (op == "REQ_STORE")       return REQ_STORE;
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
            req.data_q.push_back(word[i*8 +: 8]);
        end
        req.size         = get_next_word(line).atoi();
        req.cached       = get_next_word(line).atoi();
        req.shareability = get_next_word(line).atoi();
        req.timestamp    = get_next_word(line).atoi();
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
        return word.substr(5, word.len()-1);
    endfunction

    function automatic int get_n_transactions;
        int fd, ret;
        string line;
        int rows = 0;
        fd = $fopen(this.txn_file, "r");
        if (fd) begin
            while (!$feof(fd)) begin
                ret = $fgets(line, fd);
                if (line != "") rows++;
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
                if (line != "") begin
                    cache_req = parse_txn(line);
                    send_req(cache_req);
                end
            end
        end else begin
            $fatal("Could not open file %s", txn_file);
        end
        $fclose(fd);
    endtask

    task send_req(input cache_req req);
        while (req.timestamp > clk_cnt) begin
            @(posedge clk_if.clk_i);
        end
        cache_req_mbx.put(req);
    endtask

    task recv_resps;
        cache_resp cache_resp;
        cache_resp_mbx.get(cache_resp);
        txns_remaining--;
    endtask

    task count_clocks;
        forever begin
            @(posedge clk_if.clk_i);
            clk_cnt++;
        end
    endtask

    task run;
        txns_remaining = get_n_transactions();
        fork
            count_clocks();
            fork
                gen_txns_from_file();
                while (txns_remaining != 0) begin
                    recv_resps();
                end
            join
        join_any
    endtask

endclass
