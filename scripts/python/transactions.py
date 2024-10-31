from random import choice, randrange, random
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
  CMO_FLUSH_NLINE = 2

class WritePolicyHint(Enum):
  WR_POLICY_WB = 2
  WR_POLICY_WT = 4

class CacheTransaction:
  def __init__(
      self,
      addr_width: int,
      data_width: int,
      mem_ranges: List[MemoryRange]
    ):
    self.addr = 0
    self.data = 0
    self.size = 0
    self.op = CacheReqOp.REQ_LOAD
    self.uncacheable = 0
    self.wr_poliy_hint = WritePolicyHint.WR_POLICY_WB
    self.mem_ranges = mem_ranges

    self.aw = addr_width
    self.dw = data_width

    self.data_min = 0
    self.data_max = (1 << self.dw) - 1

  def get_rand_mem_range(self, noncached_odds=0.2):
    # Separate memory ranges into cached and non-cached ones
    # So that we can generate relatively more cached requestes 
    cached = []
    noncached = []
    for memrange in self.mem_ranges:
      if memrange.cached:
        cached.append(memrange)
      else:
        noncached.append(memrange)
    if random() < noncached_odds:
      return choice(noncached)
    return choice(cached)

  def get_rand_op(self):
    allowed_ops = [
      CacheReqOp.REQ_LOAD
    ]
    return choice(allowed_ops)

  def get_rand_addr(self, mem_range: MemoryRange):
    return randrange(mem_range.start_addr, mem_range.end_addr, self.dw//8)

  def get_rand_wr_policy_hint(self):
    return choice(list(WritePolicyHint))

  def get_rand_size(self):
    return int(log2(self.dw))

  def get_rand_data(self, op: CacheReqOp):
    if op in [CacheReqOp.REQ_STORE]:
      return randrange(self.data_min, self.data_max)
    else:
      return 0

  def get_rand_uncacheable(self, uncacheable_odds=0.1):
    if random() <= uncacheable_odds:
      return 1
    return 0

  def randomize(self):
    self.op   = self.get_rand_op()
    mem_range = self.get_rand_mem_range()
    self.addr = self.get_rand_addr(mem_range)
    self.data = self.get_rand_data(self.op)
    self.size = self.get_rand_size()
    self.uncacheable = int(not mem_range.cached)
    self.wr_policy_hint = self.get_rand_wr_policy_hint()

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

  def generate_rand_sequence(self, n_transactions):
    for _ in range(n_transactions):
      txn = CacheTransaction(
        self.aw, self.dw, self.mem_ranges)
      txn.randomize()
      self.sequence.append(txn)

  def generate_file(self, filename):
    first = True
    with open(filename, "w") as file:
      for txn in self.sequence:
        if not first:
          file.write("\n")
        else:
          first = False
        row = [
          txn.op.name, hex(txn.addr), hex(txn.data),
          txn.size, txn.uncacheable, txn.wr_policy_hint.value
        ]
        file.write((self.separator.join(str(x) for x in row)))


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
