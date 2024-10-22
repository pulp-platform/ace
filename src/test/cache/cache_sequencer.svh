`ifndef _CACHE_TEST_PKG
*** INCLUDED IN cache_test_pkg ***
`endif
class cache_sequencer #(
    parameter int AW = 32,
    parameter string txn_file = "",
    parameter type aw_beat_t = logic,
    parameter type ar_beat_t = logic,
    parameter type w_beat_t = logic
);
    typedef struct {
        aw_beat_t aw_beat;
        ar_beat_t ar_beat;
    } st_beat_t;

    mailbox #(cache_req)  cache_req_mbx;
    mailbox #(cache_resp) cache_resp_mbx;
    mailbox #(aw_beat_t)  aw_mbx_o;
    mailbox #(ar_beat_t)  ar_mbx_o;
    mailbox #(w_beat_t)   w_mbx_o;

    byte delimiter = " ";

    function new(
        mailbox #(cache_req)  cache_req_mbx,
        mailbox #(cache_resp) cache_resp_mb,
        mailbox #(aw_beat_t)  aw_mbx_o,
        mailbox #(ar_beat_t)  ar_mbx_o,
        mailbox #(w_beat_t)   w_mbx_o
    );
        this.cache_req_mbx  = cache_req_mbx;
        this.cache_resp_mbx = cache_resp_mbx;
        this.aw_mbx_o = aw_mbx_o;
        this.ar_mbx_o = ar_mbx_o;
        this.w_mbx_o  = w_mbx_o;
    endfunction

    function automatic ar_beat_t parse_read_beat(string line);
        ar_beat_t ar_beat = new;
        ar_beat.snoop  = get_next_word(line).atoi();
        ar_beat.addr   = get_next_word(line).atohex();
        ar_beat.id     = get_next_word(line).atoi();
        ar_beat.len    = get_next_word(line).atoi();
        ar_beat.size   = get_next_word(line).atoi();
        ar_beat.burst  = get_next_word(line).atoi();
        ar_beat.lock   = get_next_word(line).atoi();
        ar_beat.cache  = get_next_word(line).atoi();
        ar_beat.prot   = get_next_word(line).atoi();
        ar_beat.qos    = get_next_word(line).atoi();
        ar_beat.region = get_next_word(line).atoi();
        ar_beat.user   = get_next_word(line).atoi();
        ar_beat.bar    = get_next_word(line).atoi();
        ar_beat.domain = get_next_word(line).atoi();
        return ar_beat;
    endfunction

    function automatic aw_beat_t parse_write_addr_beat(string line);
        aw_beat_t aw_beat = new;
        aw_beat.snoop    = get_next_word(line).atoi();
        aw_beat.addr     = get_next_word(line).atohex();
        aw_beat.id       = get_next_word(line).atoi();
        aw_beat.len      = get_next_word(line).atoi();
        aw_beat.size     = get_next_word(line).atoi();
        aw_beat.burst    = get_next_word(line).atoi();
        aw_beat.lock     = get_next_word(line).atoi();
        aw_beat.cache    = get_next_word(line).atoi();
        aw_beat.prot     = get_next_word(line).atoi();
        aw_beat.qos      = get_next_word(line).atoi();
        aw_beat.region   = get_next_word(line).atoi();
        aw_beat.user     = get_next_word(line).atoi();
        aw_beat.bar      = get_next_word(line).atoi();
        aw_beat.domain   = get_next_word(line).atoi();
        aw_beat.atop     = get_next_word(line).atoi();
        aw_beat.awunique = get_next_word(line).atoi();
        return aw_beat;
    endfunction

    function automatic st_beat_t parse_txn(string line);
        aw_beat_t beat;
        string txn_type, payload, txn_and_payload;
        st_beat_t ret_st;
        ret_st.aw_beat = new;
        ret_st.ar_beat = new;
        txn_type = get_next_word(line);
        $display(txn_type);
        if (txn_type == "READ") begin
            ret_st.ar_beat = parse_read_beat(line);
            $display("Read found");
        end else if (txn_type == "WRITE") begin
            $display("Write found");
            ret_st.aw_beat = parse_write_addr_beat(line);
        end else begin
            $error("Illegal transaction type found");
        end
        return ret_st;
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

    // No cache lookup needed
    task gen_read_txn(ar_beat_t beat);
        ar_mbx_o.put(beat);
    endtask

    // Cache lookup needed
    task gen_write_txn(aw_beat_t aw_beat);
        cache_req c_req = new;
        cache_resp c_resp;
        c_req.addr = aw_beat.addr;
        c_req.len = aw_beat.len;
        c_req.size = aw_beat.size;
        c_req.read = 1;
        cache_req_mbx.put(c_req);
        cache_resp_mbx.get(c_resp);
        if (!c_resp.hit) begin
            $info("A non-hitting write request detected - ignored");
            return;
        end
        aw_mbx_o.put(aw_beat);
        while (c_resp.data_q.size > 0) begin
            w_beat_t w_beat;
            int unsigned wdata;
            wdata = c_resp.data_q.pop_front();
            w_beat.data = wdata;
            w_beat.strb = '1;
            w_beat.user = aw_beat.user;
            if (c_resp.data_q.size() == 0) begin
                w_beat.last = 1'b1;
            end else begin
                w_beat.last = 1'b0;
            end
            w_mbx_o.put(w_beat);
        end
    endtask

    task gen_txns_from_file;
        int fd;
        string line;
        st_beat_t ret_st;
        fd = $fopen(txn_file, "r");
        if (fd) begin
            while (!$feof(fd)) begin
                $fgets(line, fd);
                ret_st = parse_txn(line);
                if (ret_st.ar_beat != null) begin
                    gen_read_txn(ret_st.ar_beat);
                end
                if (ret_st.aw_beat != null) begin
                    gen_write_txn(ret_st.aw_beat);
                end
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