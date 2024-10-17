radix define WriteSnoop {
    3'b000  "WrNoSnp/WrUnq/Br"
    3'b001  "WriteLineUnique"
    3'b010  "WriteClean"
    3'b011  "WriteBack"
    3'b100  "Evict"
    3'b101  "WriteEvict"
}

radix define ReadSnoop {
    4'b0000  "RdNoSnp/RdOnce/Br"
    4'b0001  "ReadShared"
    4'b0010  "ReadClean"
    4'b0011  "ReadNotSharedDirty"
    4'b0111  "ReadUnique"
    4'b1011  "CleanUnique"
    4'b1100  "MakeUnique"
    4'b1000  "CleanShared"
    4'b1001  "CleanInvalid"
    4'b1101  "MakeInvalid"
    4'b1110  "DVMComplete"
    4'b1111  "DVMMessage"
}