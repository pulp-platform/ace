from random import choice, randrange, choices
from enum import Enum
from math import log2
from common import MemoryRange
from typing import List

class ReadSnoopType(Enum):
  READNOSNOOP = 0
  READONCE = 0
  READSHARED = 1
  READCLEAN = 2
  READNOTSHAREDDIRTY = 3
  READUNIQUE = 7
  CLEANUNIQUE = 11
  MAKEUNIQUE = 12
  CLEANSHARED = 8
  CLEANINVALID = 9
  MAKEINVALID = 13
  BARRIER = 0
  DMVCOMPLETE = 14
  DVMMESSAGE = 15

class WriteSnoopType(Enum):
  WRITENOSNOOP = 0
  WRITEUNIQUE = 0
  WRITELINEUNIQUE = 1
  WRITECLEAN = 2
  WRITEBACK = 3
  EVICT = 4
  WRITEEVICT = 5
  BARRIER = 0

class BurstType(Enum):
  FIXED = 0
  INCR = 1
  WRAP = 2

class CacheReqOp(Enum):
  REQ_LOAD = 0
  REQ_STORE = 1
  #CMO_FLUSH_NLINE = 2

class WritePolicyHint(Enum):
  WR_POLICY_WB = 2
  WR_POLICY_WT = 4

class CacheTransaction:
  def __init__(
      self,
      addr: int,
      op: CacheReqOp,
      data: int = 0,
      size: int = 0,
      shareability: int = 0,
      cached: bool = False,
      time: int = 0,
  ):
    """
    Parameters
    ==========
      addr
        Request address.
      op
        Operation. Type CacheReqOp.
      data
        Write data.
      size
        Size of operation as in AXI AxSIZE.
      shareability
        Shareable domain. Currently non-shared (0), inner shared (1),
        and system (3) supported.
      cached
        Whether request is cached.
      time
        The time stamp to send the request. In clock steps after reset.
        If 0 (default), it will be sent as soon as possible.
    """
    self.addr = addr
    self.data = data
    self.op = op
    self.size = size
    self.shareability = shareability
    self.cached = cached
    self.time = time

class CacheTransactionSequence:
  def __init__(
    self,
    addr_width,
    data_width,
    mem_ranges: List[MemoryRange]
    ):
    self.aw = addr_width
    self.dw = data_width
    self.mem_ranges = mem_ranges
    self.sequence : list[CacheTransaction] = []
    self.separator = " "

  def add_transaction(self, txn: CacheTransaction):
    self.sequence.append(txn)

  def generate_rand_sequence(self, n_transactions):
    for _ in range(n_transactions):
      txn = self.gen_rand_transaction()
      self.sequence.append(txn)

  def get_rand_mem_range(self):
    return choice(self.mem_ranges)

  def get_rand_data(self):
    return randrange(0, (1 << self.dw) - 1)

  def gen_rand_transaction(self):
    mem_range = self.get_rand_mem_range()
    addr = mem_range.get_rand_cached_shared_addr(self.dw // 8)
    shareability = 1
    op = choice(list(CacheReqOp))
    if op == CacheReqOp.REQ_LOAD:
      cached = True
    else:
      # 20% chance to generate uncached request
      cached = choices([True, False], weights=[80, 20], k=1)[0]
    data = self.get_rand_data()
    size = int(log2(self.dw))
    return CacheTransaction(
      addr=addr,
      op=op,
      data=data,
      size=size,
      shareability=shareability,
      cached=cached,
      time=0
    )

  def generate_file(self, filename):
    first = True
    with open(filename, "w") as file:
      for txn in self.sequence:
        if not first:
          file.write("\n")
        else:
          first = False
        file.write(
          f"OPER:{txn.op.name} ADDR:{txn.addr:0{self.aw // 4}x} "
          f"DATA:{txn.data:0{self.dw // 4}x} SIZE:{txn.size} "
          f"CACH:{int(txn.cached)} SHAR:{txn.shareability} TIME:{txn.time}"
        )


if __name__ == "__main__":
  import argparse
  parser = argparse.ArgumentParser(
    description=('Script to generate random transactions')
  )
  parser.add_argument(
    'file',
    type=str,
    help='The filename where data will be written'
  )
  parser.add_argument(
    'n',
    type=int,
    help='Number of transactiosn'
  )
  args = parser.parse_args()
  cts = CacheTransactionSequence()
  cts.generate_rand_sequence(args.n)
  cts.generate_file(args.file)
