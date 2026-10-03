from odoo import fields, models


class ProductTemplate(models.Model):
    _inherit = 'product.template'

    ilock_reorder_point = fields.Float(
        string='I LOCK Reorder Alert',
        help='Operational alert threshold for this product. Use Odoo reordering rules for automatic procurement per warehouse.',
    )
    ilock_storage_note = fields.Char(string='I LOCK Storage Note')
