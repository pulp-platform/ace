from cache_state import CacheState
from memory_state import MemoryState
from common import MemoryRange
from transactions import CacheTransactionSequence
from random import random, randint

class CacheCoherencyTest:
  def __init__(
      self,
      n_caches: int,
      n_transactions: int
      ):
    self.aw = 32
    self.dw = 32
    self.word_width = 32
    self.cacheline_words = 4
    self.ways = 2
    self.sets = 1024
    self.n_caches = n_caches
    self.n_transactions = n_transactions
    self.cacheline_bytes = \
      self.cacheline_words * self.word_width // 8
    self.caches = n_caches*[
      CacheState(
        addr_width=self.aw,
        data_width=self.dw,
        word_width=self.word_width,
        cacheline_words=self.cacheline_words,
        ways=self.ways,
        sets=self.sets
      )
    ]
    self.mem_ranges : list[MemoryRange] = []

    self.gen_memory_ranges()

    self.mem_state = MemoryState(self.mem_ranges)
    self.mem_state.gen_rand_mem()
    self.mem_state.save_rand_mem()

    self.transactions = self.n_caches*[
      CacheTransactionSequence(
      self.aw, self.dw, self.mem_ranges
      )
    ]

    self.gen_transactions()
    self.init_caches()
    self.save_caches()

  def gen_memory_ranges(self):
    mem_range = MemoryRange(
      cached=True, start_addr=0, end_addr=0x0010_0000)
    self.mem_ranges.append(mem_range)
    mem_range = MemoryRange(
      cached=False, start_addr=0x0010_0000, end_addr=0x0020_0000)
    self.mem_ranges.append(mem_range)

  def gen_transactions(self):
    for i, txn_seq in enumerate(self.transactions):
      txn_seq.generate_rand_sequence(self.n_transactions)
      txn_seq.generate_file(f"txns_{i}.txt")

  def rand_choice(self, odds=0.5):
    """Returns true for given odds"""
    if random() < odds:
      return True
    return False

  def rand_index(self, n):
    """Return random index from 0 to n"""
    return randint(0, n)

  def rand_cache_index(self):
    return self.rand_index(self.rand_index(self.n_caches))

  def rand_sharers(self, owner):
    sharers = []
    for idx in range(self.n_caches):
      if idx == owner:
        sharers.append(True)
      else:
        sharers.append(self.rand_choice())

  def rand_cacheline_state(self):
    return 

  def init_caches(self):
    for cache in self.caches:
      cache.init_cache()
    self.caches[0].set_entry(0x20, self.cacheline_bytes*[0xF], [True, False, False])

  def save_caches(self):
    for i, cache in enumerate(self.caches):
      cache.save_state(
        data_file=f"data_mem_{i}.mem",
        tag_file=f"tag_mem_{i}.mem",
        state_file=f"state_{i}.mem"
      )


if __name__ == "__main__":
  cct = CacheCoherencyTest(4, 100)