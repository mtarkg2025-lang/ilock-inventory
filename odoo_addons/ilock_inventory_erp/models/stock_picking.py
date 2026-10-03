from odoo import fields, models


class StockPicking(models.Model):
    _inherit = 'stock.picking'

    ilock_document_ref = fields.Char(string='I LOCK Document Reference', index=True, copy=False)
    ilock_shift = fields.Selection(
        [('day', 'Day'), ('evening', 'Evening'), ('night', 'Night')],
        string='Production Shift',
        default='day',
    )
    ilock_requested_by = fields.Char(string='Requested By')
    ilock_operation_note = fields.Text(string='I LOCK Operation Note')
