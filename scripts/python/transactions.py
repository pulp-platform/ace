from random import choice, randrange
from enum import Enum

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

class TransactionType(Enum):
  READ = 0
  WRITE = 1

class CacheTransaction:
  def __init__(self):
    self.txn_type = TransactionType.READ
    self.addr = 0
    self.snoop = 0
    self.id = 0
    self.len = 0
    self.size = 0
    self.burst = BurstType.INCR
    self.lock = 0 
    self.cache = 0
    self.prot = 0
    self.qos = 0
    self.region = 0
    self.user = 0
    self.bar = 0
    self.domain = 0
    self.atop = 0
    self.snoop = ReadSnoopType.READNOSNOOP
    self.awunique = 0

    self.addr_min = 0
    self.addr_max = 0x1000_0000

  def get_rand_txn(self):
    return choice(list(TransactionType))

  def get_rand_addr(self, min, max, step=4):
    return randrange(min, max, step)

  def get_rand_snoop(self, txn_type):
    if txn_type == TransactionType.READ:
      return choice(list(ReadSnoopType))
    elif txn_type == TransactionType.WRITE:
      return choice(list(WriteSnoopType))
    else:
      raise KeyError("Incorrect transaction type")

  def get_rand_len(self, addr, size):
    # TODO Calculate that address doesn't cross cache boundary
    return 1

  def get_rand_size(self):
    # TODO
    return 6

  def get_rand_burst(self):
    #return choice(list(BurstType))
    return BurstType.INCR

  def get_rand_domain(self):
    # TODO
    return 0

  def randomize(self):
    self.txn_type = self.get_rand_txn()
    self.addr = self.get_rand_addr(self.addr_min, self.addr_max)
    self.snoop = self.get_rand_snoop(self.txn_type)
    self.size = self.get_rand_size() 
    self.len = self.get_rand_len(self.addr, self.size)
    self.burst = self.get_rand_burst()
    self.lock = 0
    self.cache = 0
    self.prot = 0
    self.qos = 0
    self.region = 0
    self.user = 0
    self.bar = 0
    self.domain = self.get_rand_domain()
    self.atop = 0
    self.awunique = 0

class CacheTransactionSequence:
  def __init__(self):
    self.sequence = []
    self.separator = " "

  def generate_rand_sequence(self, n_transactions):
    for _ in range(n_transactions):
      txn = CacheTransaction()
      txn.randomize()
      self.sequence.append(txn)

  def generate_file(self, filename):
    with open(filename, "w") as file:
      for txn in self.sequence:
        row = [
          txn.txn_type.name, txn.snoop.value, hex(txn.addr), txn.id, txn.len,
          txn.size, txn.burst.value, txn.lock, txn.cache,
          txn.prot, txn.qos, txn.region, txn.user,
          txn.bar, txn.domain, txn.atop, txn.awunique
        ]
        file.write((self.separator.join(str(x) for x in row)) + "\n")


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
