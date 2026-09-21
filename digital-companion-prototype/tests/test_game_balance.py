import copy,hashlib,json,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import apply_game_balance as balance

class BalanceTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.workbook=balance.ROOT/'Game Balance.xlsx'
  cls.sheets=balance.read_xlsx(cls.workbook)
 def edit(self,sheet,row,column,value):
  sheets=copy.deepcopy(self.sheets)
  cells=next(cells for number,cells in sheets[sheet] if number==row)
  cells[column]=value
  return sheets
 def test_real_workbook_roundtrip(self):
  exported=balance.import_workbook(self.workbook)
  self.assertEqual(exported,json.loads((balance.ROOT/'assets/balance/game-balance.json').read_text()))
  balance.validate_godot(exported)
 def test_edit_changes_runtime_bundle(self):
  sheets=self.edit('Creatures',2,3,48)
  for number,cells in sheets['Moves'][1:]:
   if cells[0]=='mend':cells[24]=0.30
  for number,cells in sheets['Training'][1:]:
   if cells[0]=='game_definitions.TRAINING/offense/gain':cells[2]=4
  for number,cells in sheets['Economy'][1:]:
   if cells[0]=='game_definitions.DECOR/pond/cost/stone':cells[2]=9
  with patch.object(balance,'read_xlsx',return_value=sheets):
   exported=balance.import_workbook(self.workbook)
  self.assertEqual(exported['tables']['creatures'][0]['hp'],48)
  self.assertEqual(next(m for m in exported['tables']['moves'] if m['id']=='mend')['heal_percent'],0.30)
  self.assertEqual(exported['settings']['game_definitions.TRAINING']['offense']['gain'],4)
  self.assertEqual(exported['settings']['game_definitions.DECOR']['pond']['cost']['stone'],9)
  balance.validate_godot(exported)
 def test_invalid_edit_is_atomic(self):
  path=balance.ROOT/'assets/balance/game-balance.json';before=path.read_bytes()
  with patch.object(balance,'read_xlsx',return_value=self.edit('Creatures',2,3,-1)):
   with self.assertRaisesRegex(ValueError,'Creatures row 2'):balance.apply(self.workbook)
  self.assertEqual(path.read_bytes(),before)
 def test_missing_move_rejected(self):
  with patch.object(balance,'read_xlsx',return_value=self.edit('Creatures',2,9,'missing|bounce_rush|heavy_slam')):
   with self.assertRaisesRegex(ValueError,'unavailable move'):balance.import_workbook(self.workbook)
 def test_duplicate_id_rejected(self):
  with patch.object(balance,'read_xlsx',return_value=self.edit('Creatures',3,0,'slime_basic')):
   with self.assertRaisesRegex(ValueError,'duplicate ID'):balance.import_workbook(self.workbook)
 def test_nonfinite_rejected(self):
  with patch.object(balance,'read_xlsx',return_value=self.edit('Creatures',2,3,float('nan'))):
   with self.assertRaisesRegex(ValueError,'finite number'):balance.import_workbook(self.workbook)

if __name__=='__main__':unittest.main()
