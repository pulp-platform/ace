from cache_state import \
  CacheState, CachelineState, \
  CachelineStateEnum, CacheSetFullException
from memory_state import MemoryState
from common import MemoryRange
from transactions import CacheTransactionSequence
from random import random, randint, choice, sample
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
      target_dir: str,
      **kwargs
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
    self.caches: list[CacheState] = []
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

    self.transactions: list[CacheTransactionSequence] = []
    for _ in range(self.n_caches):
      self.transactions.append(
        CacheTransactionSequence(
        self.aw, self.dw, self.mem_ranges
        )
      )
    self.gen_transactions()

    self.init_caches(n_inited_lines=100)
    self.save_caches()

  def gen_memory_ranges(self):
    mem_range = MemoryRange(
      cached=True, start_addr=0, end_addr=0x0010_0000
    )
    self.mem_ranges.append(mem_range)
    mem_range = MemoryRange(
      cached=False, start_addr=0x0010_0000, end_addr=0x0020_0000
    )
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

  def get_rand_cacheline_data(self):
    data = []
    for _ in range(self.cacheline_bytes):
      data.append(randint(0, 255))

  def get_rand_mem_range(self, type="both") -> MemoryRange:
    rand_pool = []
    for mem_range in self.mem_ranges:
      cache_allwd = type in ["cached", "both"]
      uncache_allwd = type in ["uncached", "both"]
      if mem_range.cached and cache_allwd:
        rand_pool.append(mem_range)
      if not mem_range.cached and uncache_allwd:
        rand_pool.append(mem_range)
    return choice(rand_pool)

  def init_caches(self, n_inited_lines):
    for cache in self.caches:
      cache.init_cache()
    for _ in range(n_inited_lines):
      # Get a random memory range
      rand_mem_range = self.get_rand_mem_range(type="cached")
      # Get a random address from that memory range
      # Aligned to cache line boundary
      addr = rand_mem_range.get_rand_addr(self.cacheline_bytes)
      # Get data from initialized memory
      data = rand_mem_range.get_data(addr, self.cacheline_bytes)
      # Select random number of masters to have that cache line
      n_masters = randint(1, self.n_caches)
      # Randomly select the master indices to have that cache line
      mst_idxs = sample(range(self.n_caches), n_masters)
      # Select whether someone will hold the line in dirty state
      dirty = self.rand_choice(odds=0.5)
      shared = len(mst_idxs) > 1
      owner = -1
      if dirty:
        # Randomly select the owner
        owner = sample(mst_idxs, 1)
      for mst_idx in mst_idxs:
        write_data = data
        if mst_idx == owner:
          # Generate random data since data is dirty
          write_data = self.get_rand_cacheline_data()
          if shared:
            state = CachelineState(CachelineStateEnum.OWNED)
          else:
            state = CachelineState(CachelineStateEnum.MODIFIED)
        else:
          if shared:
            state = CachelineState(CachelineStateEnum.SHARED)
          else:
            state = CachelineState(CachelineStateEnum.EXCLUSIVE)
        try:
          self.caches[mst_idx].set_entry(
            addr,
            write_data,
            state.get_state_bits()
          )
        except CacheSetFullException:
          pass

  def save_caches(self):
    for i, cache in enumerate(self.caches):
      cache.save_state(
        data_file=os.path.join(self.target_dir, f"data_mem_{i}.mem"),
        tag_file=os.path.join(self.target_dir, f"tag_mem_{i}.mem"),
        state_file=os.path.join(self.target_dir, f"state_{i}.mem")
      )


if __name__ == "__main__":
  import argparse
  from random import seed
  import numpy as np
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
  parser.add_argument(
    '--seed',
    type=int,
    help="Seed for the simulation",
    default=None,
    nargs='?'
  )
  parsed_args = vars(parser.parse_args())
  if parsed_args.get("seed", None):
    seed(parsed_args["seed"])
    np.random.seed(parsed_args["seed"])
  cct = CacheCoherencyTest(**parsed_args)