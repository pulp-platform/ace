from cache_state import CacheState
from memory_state import MemoryState
from common import MemoryRange
from transactions import CacheTransactionSequence
from random import random, randint
import os

class CacheCoherencyTest:
  def __init__(
      self,
      addr_width: int,
      data_width: int,
      word_width: int,
      cacheline_words: int,
      ways: int,
      sets: int,
      n_caches: int,
      n_transactions: int,
      target_dir: str
      ):
    self.aw = addr_width
    self.dw = data_width
    self.word_width = word_width
    self.cacheline_words = cacheline_words
    self.ways = ways
    self.sets = sets
    self.n_caches = n_caches
    self.n_transactions = n_transactions
    self.target_dir = target_dir

    self.cacheline_bytes = \
      self.cacheline_words * self.word_width // 8
    self.caches = []
    for _ in range(0, n_caches):
      self.caches.append(
        CacheState(
          addr_width=self.aw,
          data_width=self.dw,
          word_width=self.word_width,
          cacheline_words=self.cacheline_words,
          ways=self.ways,
          sets=self.sets
        )
      )
    self.mem_ranges : list[MemoryRange] = []

    self.gen_memory_ranges()

    self.mem_state = MemoryState(self.mem_ranges)
    self.mem_state.gen_rand_mem()
    self.mem_state.save_mem(
      file=os.path.join(self.target_dir, "main_mem.mem"))

    self.transactions = []
    for _ in range(self.n_caches):
      self.transactions.append(
        CacheTransactionSequence(
        self.aw, self.dw, self.mem_ranges
        )
      )
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
      txn_seq.generate_file(
        os.path.join(self.target_dir, f"txns_{i}.txt"))

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
    self.caches[0].set_entry(
      0x20, self.cacheline_bytes*[0xA], [True, False, False])

  def save_caches(self):
    for i, cache in enumerate(self.caches):
      cache.save_state(
        data_file=os.path.join(self.target_dir, f"data_mem_{i}.mem"),
        tag_file=os.path.join(self.target_dir, f"tag_mem_{i}.mem"),
        state_file=os.path.join(self.target_dir, f"state_{i}.mem")
      )


if __name__ == "__main__":
  import argparse
  parser = argparse.ArgumentParser(
    description=('Script to write data to a file'
                 'based on address space.')
  )
  parser.add_argument(
    '--addr_width',
    type=int,
    help='AXI address width'
  )
  parser.add_argument(
    '--data_width',
    type=int,
    help='AXI data width'
  )
  parser.add_argument(
    '--word_width',
    type=int,
    help='Width of a word in the cache'
  )
  parser.add_argument(
    '--cacheline_words',
    type=int,
    help='Number of words in a cacheline'
  )
  parser.add_argument(
    '--ways',
    type=int,
    help='Number of ways in the cache'
  )
  parser.add_argument(
    '--sets',
    type=int,
    help='Number of sets in the cache'
  )
  parser.add_argument(
    '--n_caches',
    type=int,
    help='Number of cached masters in the test'
  )
  parser.add_argument(
    '--n_transactions',
    type=int,
    help='Number of transactions generated per cached master'
  )
  parser.add_argument(
    '--target_dir',
    type=str,
    help='Target directory for generated files'
  )
  parsed_args = vars(parser.parse_args())
  cct = CacheCoherencyTest(**parsed_args)